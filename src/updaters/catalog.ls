require! <[
    ../queries
    ../fetch-item
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

module.exports = (comment, date-to-fetch-to, force = no) ->
    debug = @debug.push "catalog"

    debug "start"

    @reset-counters!

    fetch = @client.InventoryService.GetFilteredInventoryItemList

    # Get the resume data for the catalog update, if any.
    debug "select-catalog-resume-page"
    err, rows <~ @db.query queries.select-catalog-resume-page
    if err
        return @emit 'error', new ErrorInfo do
            error: err
            message: "could not run database query, \
                at updater.catalog,select-last-update-checkpoint-date"
            stage: "catalog:pre-run-checks"
            fatal: true

    date-to-fetch-from = new Date "2000"

    current-page = 1

    if not force
    and date-to-fetch-to
    and rows.length is not 0
        # Then we can make the current-page the last progress run page.
        current-page := rows[0].page_id

    if comment
        comment := comment + " || "
    else
        comment := ""

    if force
        debug "using force"
        comment := comment + "Forceful update per request. \
            Existing data will be truncated."

    continuing = false

    if not date-to-fetch-to
        date-to-fetch-to := new Date
    else
        debug "continuing catalog, #{date-to-fetch-to}"
        continuing := true
        comment := comment + "Continuing catalog update last \
            run on #{date-to-fetch-to.toGMTString!} from page #{current-page}."

    start-date = new Date

    async.waterfall [
        (next) ~>
            # Insert a "catalog:reset" run log if we are forcing an update.
            if force
                debug "resetting catalog"
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
                debug "truncating tables"
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
            # Insert the update:checkpoint log entry if this is not a resume.
            if continuing
                return next!

            debug "updates checkpoint"
            err <~ @db.query queries.insert-run-log, [
                'updates'
                'checkpoint'
                start-date
                ''
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

            return next!
        (next) ~>
            # Insert the catalog:start run log entry.
            debug "insert catalog:start"
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
            debug "emit update-start"
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

            page = pages!
            debug "initialized pages generator"

            # TODO: Make function that checks errors, and handles them

            async.forever do
                (callback) ~>
                    # TODO: Get the next page.
                    debug "fetching page #{current-page}"
                    debug "inserting catalog:progress"
                    err <~ @db.query queries.insert-run-log, [
                        'catalog'
                        'progress'
                        new Date
                        ''
                        current-page
                        null
                    ]
                    if err then return callback err

                    @emit 'update-progress', new UpdateProgressInfo do
                            type: 'catalog'
                            date: new Date
                            date-started: start-date
                            comment: ''
                            current-page: current-page
                            added: @items-added
                            changed: @items-changed
                            deleted: @items-deleted

                    err, result <~ fetch page.next!.value
                    debug "fetched page"
                    if err then return callback err

                    result = result.GetFilteredInventoryItemListResult # ugh

                    # Check if the message code is 0.
                    #   If it's anything other than that, then we need to throw
                    #   an error.
                    if result.MessageCode is not 0
                        return callback new Error "MessageCode is not 0, \
                            but is #{result.MessageCode} with message: \
                            #{result.Message}"

                    data = result.ResultData.InventoryItemResponse # u g h

                    if data.length is 0
                        debug "all items fetched"
                        return callback "OKAY"

                    q = async.queue (item, done) ~>
                        process-individual-item.call @, item, done

                    q.drain = ~>
                        debug "done processing items, \
                            fetching next page"
                        callback!

                    q.push data, (err, sku) ~>
                        debug = (@debug.push "catalog").push "queue"
                        if err
                            debug "got error from an item during processing"
                            q.kill!
                            return callback err

                        # Try to get the item from the DB, and then feed it into
                        #   the EventEmitter.
                        err, item <~ fetch-item @db~query, sku
                        if err
                            debug "got error from an item during fetching"
                            q.kill!
                            return callback err

                        @emit 'new-item', new NewItemInfo do
                            type: 'catalog'
                            date: new Date
                            item: item
                            comment: comment

                (err) ~>
                    if err is not "OKAY"
                        debug "err is NOT 'OKAY'"
                        return @emit 'error', new ErrorInfo do
                            error: err
                            message: "could not process/query items"
                            stage: "catalog:get-next-page"
                            fatal: true

                    debug "EVERYTHING WENT OKAY, \
                        ALL ITEMS ARE DONE"
                    # TODO: Clean up.

    ], (err) ->
        throw err


process-individual-item = (item, done) ->
    debug = (@debug.push "catalog").push "process-individual-item"

    debug "inserting base data"
    err <~ @db.query queries.replace-inventory-item, [
        new Date
        item.Sku
        item.Title
        item.Subtitle
        item.ShortDescription
        item.Description
        item.Weight
        item.SupplierCode
        item.WarehouseLocation
        item.TaxProductCode
        item.FlagStyle
        item.FlagDescription
        item.IsBlocked
        item.BlockComment
        item.ASIN
        item.ISBN
        item.UPC
        item.MPN
        item.EAN
        item.Manufacturer
        item.Brand
        item.Condition
        item.Warranty
        item.ProductMargin
        item.SupplierPO
        item.HarmonizedCode
        item.Height
        item.Length
        item.Width
        item.Classification
    ]
    if err then return done err

    debug "inserting quantity data"
    quan = item.Quantity
    err <~ @db.query queries.replace-inventory-quantity-data, [
        item.Sku
        quan.Available
        quan.OpenAllocated
        quan.OpenUnallocated
        quan.PendingCheckout
        quan.PendingPayment
        quan.PendingShipment
        quan.Total
        quan.OpenAllocatedPooled
        quan.OpenUnallocatedPooled
        quan.PendingCheckoutPooled
        quan.PendingPaymentPooled
        quan.PendingShipmentPooled
        quan.TotalPooled
    ]
    if err then return done err

    debug "inserting price data"
    pric = item.PriceInfo
    err <~ @db.query queries.replace-inventory-price-data, [
        item.Sku
        pric.Cost
        pric.RetailPrice
        pric.StartingPrice
        pric.ReservePrice
        pric.TakeItPrice
        pric.SecondChanceOfferPrice
        pric.StorePrice
    ]
    if err then return done err

    debug "processed item"
    done null, item.Sku