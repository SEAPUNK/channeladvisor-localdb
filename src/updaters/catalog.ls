require! <[
    ../queries
    async
    debug
    ./common
]>

{inspect} = require 'util'

{
    UpdatesUpdateInfo
    CatalogUpdateInfo
    UpdateStartInfo
    UpdateStopInfo
    UpdateDoneInfo
    UpdateProgressInfo
    ItemUpdateInfo
    ErrorInfo
} = require '../info-objects/'

module.exports = (comment, date-to-fetch-to, force = no) ->
    d = debug "CALDB:updater:catalog"
    d "start"

    date-to-fetch-from = new Date "2000"
    current-page = 1
    start-date = new Date
    if comment
        comment := comment + " || "
    else
        comment := ""


    @reset-stats!

    ###
    # Fetch resume data
    d "RunLog.get-last-catalog-update-progress"
    err, runlog <~ @models.RunLog.get-last-catalog-update-progress
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at catalog:RunLog.get-last-catalog-update-progress"
            stage: "catalog:pre-run-checks"

    ###
    # Determine resume page
    if not force
    and date-to-fetch-to
    and runlog.length is not 0
        # Then we can make the current-page the last progress run page.
        current-page := runlog[0].page-id
        d "changing current-page to #{current-page}"

    ###
    # Determine force update
    if force
        d "using force"
        comment := comment + "Forceful update per request. \
            Existing data will be truncated."

    ###
    # Determine date to fetch to and if continuing
    continuing = no
    if not date-to-fetch-to
        date-to-fetch-to := new Date
    else
        d "continuing catalog, #{date-to-fetch-to}"
        continuing := yes
        comment := comment + "Continuing catalog update last \
            run on #{date-to-fetch-to.toGMTString!} from page #{current-page}."

    async.waterfall [
        ###
        # Truncate tables (including RunLog!) if force
        (next) ~>
            if not force then return next!
            d "truncating tables"
            async.waterfall [
                (nxt) ~>
                    @unpromise (@db.query "SET FOREIGN_KEY_CHECKS = 0"), nxt
                (_, nxt) ~>
                    @unpromise @models.InventoryItemPrice.truncate!, nxt
                (_, nxt) ~>
                    @unpromise @models.InventoryItemQuantity.truncate!, nxt
                (_, nxt) ~>
                    @unpromise @models.InventoryItemAttribute.truncate!, nxt
                (_, nxt) ~>
                    @unpromise @models.InventoryItem.truncate!, nxt
                (_, nxt) ~>
                    @unpromise @models.RunLog.truncate!, nxt
                (_, nxt) ~>
                    @unpromise (@db.query "SET FOREIGN_KEY_CHECKS = 1"), nxt
            ], (err) ~>
                if err then return @errout do
                    error: err
                    message: "could not run database query, \
                        at catalog:InventoryItem.truncate cascade: true"
                    stage: "catalog:truncate-inventory"
                return next!

        ###
        # Insert catalog:reset if force
        (next) ~>
            if not force then return next!
            d "resetting catalog"
            err <~ @unpromise @models.RunLog.create do
                updater: 'catalog'
                event: 'reset'
                date: start-date
                comment: "Forceful reset of catalog requested."
            if err
                return @errout do
                    error: err
                    message: "could not run database query, \
                        at catalog:RunLog.create"
                    stage: "catalog:insert-force-log"
            return next!

        ###
        # Insert update:checkpoint if not continuing
        (next) ~>
            if continuing then return next!

            d "updates checkpoint"
            err <~ @unpromise @models.RunLog.create do
                updater: 'updates'
                event: 'checkpoint'
                date: start-date
            if err
                return @errout do
                    error: err
                    message: "could not run database query, \
                        at catalog:RunLog.create"
                    stage: "catalog:update-checkpoint"

            return next!

        ###
        # Insert catalog:start
        (next) ~>
            d "insert catalog:start"
            err <~ @unpromise @models.RunLog.create do
                updater: 'catalog'
                event: 'start'
                date: start-date
                comment: comment
            if err
                return @errout do
                    error: err
                    message: "could not run database query, \
                        at catalog:RunLog.create"
                    stage: "catalog:start-run"

            next!

        ###
        # Emit update-start
        (next) ~>
            # emit the update-start event, then start fetching.
            d "emit update-start"
            @emit 'update-start', new UpdateStartInfo do
                type: 'catalog'
                date: start-date
                info: new CatalogUpdateInfo do
                    date-from: date-to-fetch-from
                    date-to: date-to-fetch-to
                    page: current-page
                comment: comment
            next!

        ###
        # Pages generator
        (next) ~>
            pages = ~>*
                loop
                    conf =
                        accountID: @account
                        itemCriteria:
                            DateRangeField: 'CreateDate'
                            DateRangeStartGMT: date-to-fetch-from.toISOString!
                            DateRangeEndGMT: date-to-fetch-to.toISOString!
                            PageNumber: current-page++
                            PageSize: 100
                        detailLevel:
                            IncludeQuantityInfo: yes
                            IncludePriceInfo: yes
                            IncludeClassificationInfo: yes
                        sortField: 'Sku'
                        sortDirection: 'Ascending'
                    yield conf
                void

            page = pages!
            d "initialized pages generator"
            next null, page

        ###
        # Page fetching
        # TODO: Make function that checks errors, and handles them

        (page, next) ~>
            start = common.get @

            handle-end = (err) ~>
                if err is not "OKAY"
                    d "err is NOT 'OKAY'"
                    return @emit 'error', new ErrorInfo do
                        error: err
                        message: "could not process/query items"
                        stage: "catalog:get-next-page"
                        fatal: true

                d "cleaning up; pushing catalog:done"

                err <~ @unpromise @models.RunLog.create do
                    updater: 'catalog'
                    event: 'done'

                if err then return @emit 'error', new ErrorInfo do
                    error: err
                    message: "could not push catalog:done"
                    stage: "catalog:cleanup"
                    fatal: true

                d "catalog-done"
                @catalog-done!

            start "catalog", page, current-page, handle-end
    ], (err) ~>
        throw err