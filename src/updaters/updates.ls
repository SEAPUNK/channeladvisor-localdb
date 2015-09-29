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

module.exports = (comment) ->
    d = debug "CALDB:updater:catalog"
    d "start"

    ###
    # Reset stats
    @reset-stats!

    ###
    # Variables
    fetch = @client.InventoryService.GetFilteredInventoryItemList

    ###
    # Fetch checkpoint
    d "RunLog.get-last-updates-checkpoint"
    err, runlog <~ @models.RunLog.get-last-updates-checkpoint
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at updates:RunLog.get-last-updates-checkpoint"
            stage: "updates:pre-run-checks"
    if runlog.length is 0
        return @errout do
            message: "no update checkpoints; this should never happen"
            stage: "updates:pre-run-checks"

    checkpoint = runlog[0]
    runlog = null

    ###
    # Fetch resume data, pt.1
    d "RunLog.get-last-incomplete-updates-start"
    err, runlog <~ @models.RunLog.get-last-incomplete-updates-start
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at updates:RunLog.get-last-incomplete-updates-start"
            stage: "updates:pre-run-checks"

    if runlog.length is not 0
        date-to-fetch-to = runlog[0].date
    runlog = null

    ###
    # Fetch resume data, pt.2
    d "RunLog.get-last-incomplete-updates-progress"
    err, runlog <~ @models.RunLog.get-last-incomplete-updates-progress
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at updates:RunLog.get-last-incomplete-updates-progress"
            stage: "updates:pre-run-checks"

    if date-to-fetch-to
    and runlog.length is not 0
        continuing = yes
        current-page = runlog[0].page-id
    runlog = null

    ###
    # Set defaults
    date-to-fetch-from = checkpoint.date

    if not current-page?
        current-page = 1

    ###
    # Set comment
    if comment
        comment := comment + " || "
    else
        comment := ""

    ###
    # Determine date to fetch to and if continuing
    continuing = false
    if not date-to-fetch-to?
        date-to-fetch-to := new Date
    else
        d "continuing updates, #{date-to-fetch-to}"
        continuing := true
        comment := comment + "Continuing 'updates' update last \
            run on #{date-to-fetch-to.toGMTString!} from page #{current-page}."

    ###
    # Set the start date
    start-date = new Date

    async.waterfall [
        ###
        # Insert updates:start
        (next) ~>
            d "insert updates:start"
            err <~ @unpromise @models.RunLog.create do
                updater: 'updates'
                event: 'start'
                date: start-date
                comment: comment
            if err
                return @errout do
                    error: err
                    message: "could not run database query, \
                        at updates:RunLog.create"
                    stage: "updates:start-run"
            set-timeout next

        ###
        # Emit update-start
        (next) ~>
            # emit the update-start event, then start fetching.
            d "emit update-start"
            @emit 'update-start', new UpdateStartInfo do
                type: 'updates'
                date: start-date
                info: new UpdatesUpdateInfo do
                    date-from: date-to-fetch-from
                    date-to: date-to-fetch-to
                    page: current-page
                comment: comment
            set-timeout next

        ###
        # Pages generator
        (next) ~>
            pages = ~>*
                loop
                    conf =
                        accountID: @account
                        itemCriteria:
                            DateRangeField: 'LastUpdateDate'
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
                        stage: "updates:get-next-page"
                        fatal: true

                d "cleaning up; \
                    pushing updates:checkpoint and updates:done"

                err <~ @unpromise @models.RunLog.create do
                    updater: 'updates'
                    event: 'checkpoint'

                if err then return @emit 'error', new ErrorInfo do
                    error: err
                    message: "could not push updates:checkpoint"
                    stage: "updates:cleanup"
                    fatal: true

                err <~ @unpromise @models.RunLog.create do
                    updater: 'updates'
                    event: 'done'

                if err then return @emit 'error', new ErrorInfo do
                    error: err
                    message: "could not push updates:done"
                    stage: "updates:cleanup"
                    fatal: true

                if not continuing
                    @emit 'update-done', new UpdateDoneInfo do
                        type: 'updates'
                        date: new Date
                        comment: comment
                        changed: @stats.changed
                        deleted: @stats.deleted

                if not continuing
                    d "selecting 'updates' updater, 5 minute delay"
                    @updates-done!
                if continuing
                    @updates-done yes

            start "updates", page, current-page, handle-end
    ], (err) ~>
        throw err