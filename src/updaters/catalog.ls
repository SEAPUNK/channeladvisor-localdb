require! <[
    ../queries
    async
]>

{
    UpdatesUpdateInfo
    CatalogUpdateInfo
    UpdateStartInfo
    UpdateStopInfo
    UpdateDoneInfo
    UpdateProgressInfo
    ErrorInfo
} = require '../info-objects/'

module.exports = (date-to-fetch-to, force = no) ->
    @logger.debug "caldb/catalog: start"

    fetch = @client.InventoryService.GetFilteredInventoryItemList

    var start-date
    current-page = 1

    @logger.debug "caldb/catalog: select-catalog-resume-page"

    # Get the resume data for the catalog update, if any.
    err, rows <~ @db.query queries.select-catalog-resume-page

    if err
        return @emit 'error', new ErrorInfo do
            error: err
            message: "could not run database query, \
                at updater.catalog,select-last-update-checkpoint-date"
            stage: "catalog:pre-run-checks"
            fatal: true

    date-to-fetch-from = new Date "2000"

    if not force
    and date-to-fetch-to
    and rows.length is not 0
        # Then we can use the progress row.
        current-page := rows[0].page_id

    comment = ""
    if force
        @logger.debug "caldb/catalog: using force"
        comment := "Forceful update per request. \
            Existing data will be truncated."

    if not date-to-fetch-to
        date-to-fetch-to := new Date
    else
        @logger.debug "caldb/catalog: continuing catalog, #{date-to-fetch-to}"
        comment := "Continuing catalog update last \
        run on #{date-to-fetch-to.toGMTString!} from page #{current-page}."


    start-date := new Date

    async.waterfall [
        (next) ~>
            # Insert a "catalog:reset" run log if we are forcing an update.
            if force
                @logger.debug "caldb/catalog: resetting catalog"
                err <~ @db.query queries.insert-run-log, [
                    'catalog'
                    'reset'
                    start-date
                    "Forceful reset of catalog requested."
                    null
                    null
                ]
                if err
                    return @emit 'error', new ErrorInfo do
                        error: err
                        message: "could not run database query, \
                            at updater.catalog,insert-run-log"
                        stage: "catalog:insert-force-log"
                        fatal: true
                return next!
            else
                return next!
        (next) ~>
            # Reset the inventory items if we're forcing.
            if force
                @logger.debug "caldb/catalog: truncating tables"
                err <~ @db.query queries.truncate-inventory
                if err
                    return @emit 'error', new ErrorInfo do
                        error: err
                        message: "could not run database query, \
                            at updater.catalog,truncate-inventory"
                        stage: "catalog:truncate-inventory"
                        fatal: true
                return next!
            else
                return next!
        (next) ~>
            # Insert the update:checkpoint log entry.
            @logger.debug "caldb/catalog: updates checkpoint"

            # TODO: If we're "continuing", shouldn't we omit the checkpoints?
            err <~ @db.query queries.insert-run-log, [
                'updates'
                'checkpoint'
                start-date
                null
                null
                null
            ]

            if err
                return @emit 'error', new ErrorInfo do
                    error: err
                    message: "could not run database query, \
                        at updater.catalog,insert-run-log"
                    stage: "catalog:update-checkpoint"
                    fatal: true


            # Insert the catalog:start run log entry.

            @logger.debug "caldb/catalog: insert catalog:start"
            err <~ @db.query queries.insert-run-log, [
                'catalog'
                'start'
                start-date
                comment
                null
                null
            ]

            if err
                return @emit 'error', new ErrorInfo do
                    error: err
                    message: "could not run database query, \
                        at updater.catalog,insert-run-log"
                    stage: "catalog:start-run"
                    fatal: true

            # emit the update-start event, then start fetching.
            @logger.debug "caldb/catalog: emit update-start"
            @emit 'update-start', new UpdateStartInfo do
                type: 'catalog'
                date: start-date
                info: new CatalogUpdateInfo do
                    date-from: date-to-fetch-from
                    date-to: date-to-fetch-to
                    page: current-page
                comment: comment

            pages = !~>*
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

            @logger.debug "caldb/catalog: initialized pages generator"
            page = pages!

            # TODO: Make function that checks errors, and handles them

            async.forever do
                (callback) ~>
                    # TODO: Get the next page.
                    @logger.debug "caldb/catalog: fetching next page"
                    err, result <~ fetch page.next!.value
                    if err then callback err
                    console.log do
                        require 'util' .inspect do
                            result
                                .GetFilteredInventoryItemListResult
                                .ResultData
                                .InventoryItemResponse
                (err) ~>
                    if err is not "OKAY"
                        @logger.debug "caldb/catalog: err is NOT 'OKAY'"
                        return @emit 'error', new ErrorInfo do
                            error: err
                            message: "could not query items"
                            stage: "updates:get-next-page"
                            fatal: true
                    # TODO: Clean up.

    ], (err) ->
        throw err