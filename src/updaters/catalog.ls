require! <[
    ../queries
    async
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
    debug = @debug.push "catalog"
    debug "start"

    ###
    # Reset stats
    @reset-stats!

    ###
    # Variables
    fetch = @client.InventoryService.GetFilteredInventoryItemList

    ###
    # Fetch resume data
    debug "RunLog.get-last-catalog-update-progress"
    err, runlog <~ @models.RunLog.get-last-catalog-update-progress
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at catalog:RunLog.get-last-catalog-update-progress"
            stage: "catalog:pre-run-checks"

    ###
    # More variables
    date-to-fetch-from = new Date "2000"
    current-page = 1

    ###
    # Determine resume page
    if not force
    and date-to-fetch-to
    and runlog.length is not 0
        # Then we can make the current-page the last progress run page.
        current-page := runlog[0].page-id
        debug "changing current-page to #{current-page}"

    ###
    # Set comment
    if comment
        comment := comment + " || "
    else
        comment := ""

    ###
    # Determine force update
    if force
        debug "using force"
        comment := comment + "Forceful update per request. \
            Existing data will be truncated."

    ###
    # Determine date to fetch to and if continuing
    continuing = false
    if not date-to-fetch-to
        date-to-fetch-to := new Date
    else
        debug "continuing catalog, #{date-to-fetch-to}"
        continuing := true
        comment := comment + "Continuing catalog update last \
            run on #{date-to-fetch-to.toGMTString!} from page #{current-page}."

    ###
    # Set the start date
    start-date = new Date

    async.waterfall [
        ###
        # Truncate tables (including RunLog!) if force
        (next) ~>
            if force
                debug "truncating tables"
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
                    next!
            else
                return next!

        ###
        # Insert catalog:reset if force
        (next) ~>
            if force
                debug "resetting catalog"
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
            else
                return next!

        ###
        # Insert update:checkpoint if not continuing
        (next) ~>
            if continuing
                return next!

            debug "updates checkpoint"
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
            debug "insert catalog:start"
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
            debug "emit update-start"
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
            debug "initialized pages generator"
            next null, page

        ###
        # Page fetching
        # TODO: Make function that checks errors, and handles them
        # TODO: .stop()
        (page, next) ~>

            async.forever do
                ###
                # Fetch next page
                (callback) ~>
                    debug "fetching page #{current-page}"

                    ###
                    # Insert catalog:progress
                    debug "inserting catalog:progress"
                    err <~ @unpromise @models.RunLog.create do
                        updater: 'catalog'
                        event: 'progress'
                        page-id: current-page

                    if err then return callback err

                    ###
                    # Emit update-progress
                    @emit 'update-progress', new UpdateProgressInfo do
                        type: 'catalog'
                        date: new Date
                        date-started: start-date
                        comment: ''
                        current-page: current-page
                        changed: @stats.changed
                        deleted: @stats.deleted

                    ###
                    # Call API for next page
                    err, result <~ fetch page.next!.value
                    if err then return callback err
                    debug "fetched page"

                    ###
                    # Process API response
                    result = result.GetFilteredInventoryItemListResult # ugh

                    # Check if the message code is 0.
                    #   If it's anything other than that, then we need to throw
                    #   an error.
                    if result.MessageCode is not 0
                        return callback new Error "MessageCode is not 0, \
                            but is #{result.MessageCode} with message: \
                            #{result.Message}"

                    data = result.{}ResultData.[]InventoryItemResponse # u g h

                    ###
                    # Check if there is any more data
                    if data.length is 0
                        debug "all items fetched"
                        return callback "OKAY"

                    ###
                    # Queue: Process individual item
                    q = async.queue do
                        (item, done) ~>
                            process-individual-item.call @, item, done
                        100 # 100 items at a time
                            #   because we don't want to wait
                            #   about an hour for each page

                    q.drain = ~>
                        debug "done processing items, \
                            fetching next page"
                        callback!

                    ###
                    # Post-process each item
                    items-left-to-fetch = data.length
                    q.push data, (err, item) ~>
                        debug = (@debug.push "catalog").push "queue"
                        if err
                            debug "got error from an item during processing"
                            q.kill!
                            return callback err

                        ###
                        # Up the counter
                        @stats.changed++

                        # ###
                        # # Get the item again,
                        # #   but with associations eager-loaded
                        # err, item <~ @unpromise @models.InventoryItem.findOne do
                        #     where:
                        #         Sku: item.Sku
                        #     include: [
                        #         * model: @models.InventoryItemAttribute
                        #           as: "Attributes"
                        #         * model: @models.InventoryItemPrice
                        #           as: "Price"
                        #         * model: @models.InventoryItemQuantity
                        #           as: "Quantity"
                        #     ]

                        # if err
                        #     debug "could not re-fetch the item"
                        #     q.kill!
                        #     return callback err

                        ###
                        # Emit item-update
                        debug "item done fetching, #{--items-left-to-fetch} left"
                        @emit 'item-update', new ItemUpdateInfo do
                            type: 'catalog'
                            date: new Date

                (err) ~>
                    if err is not "OKAY"
                        debug "err is NOT 'OKAY'"
                        return @emit 'error', new ErrorInfo do
                            error: err
                            message: "could not process/query items"
                            stage: "catalog:get-next-page"
                            fatal: true

                    debug "cleaning up; pushing catalog:done"

                    err <~ @unpromise @models.RunLog.create do
                        updater: 'catalog'
                        event: 'done'

                    if err then return @emit 'error', new ErrorInfo do
                        error: err
                        message: "could not push catalog:done"
                        stage: "catalog:cleanup"
                        fatal: true

                    debug "selecting 'updates' updater"
                    @catalog-done!

    ], (err) ~>
        throw err


process-individual-item = (item-data, callback) ->
    debug = (@debug.push "catalog").push "process-individual-item"

    ###
    # Insert base data
    debug "inserting data"
    err, item <~ create-item.call @, item-data
    if err then return callback err

    ###
    # Insert attribute data
    debug "inserting attributes"
    err, item <~ set-item-attributes.call @, item
    if err then return callback err

    ###
    # Callback
    debug "processed item"
    callback null, item

create-item = (item-data, callback) ->
    ###
    # Separate data
    quantity-data = delete item-data.Quantity
    price-data = delete item-data.PriceInfo

    ###
    # Initialize or find the current inventory item
    err, item <~ @unpromise.spread @models.InventoryItem.find-or-create do
        where:
            Sku: delete item-data.Sku
    if err then return callback err

    item = item[0]

    ###
    # Update the item with the data
    err <~ @unpromise item.update item-data
    if err then return callback err


    create-price = (callback) ~>
        ###
        # Create or update InventoryItemPrice association
        err, price <~ @unpromise item.getPrice!
        if err then return callback err
        if not price[0]
            err <~ @unpromise item.createPrice price-data
            return callback err
        else
            err <~ @unpromise price[0].update price-data
            return callback err

    create-quantity = (callback) ~>
        ###
        # Create or update InventoryItemQuantity association
        err, quantity <~ @unpromise item.getQuantity!
        if err then return callback err
        if not quantity[0]
            err <~ @unpromise item.createQuantity quantity-data
            return callback err
        else
            err <~ @unpromise quantity[0].update quantity-data
            return callback err

    err <~ create-price
    if err then return callback
    err <~ create-quantity
    if err then return callback

    return callback null, item

set-item-attributes = (item, callback) ->
    debug = (@debug.push "catalog").push "set-item-attributes"

    debug "making api call"
    ###
    # Make the API call for the item
    fetch = @client.InventoryService.GetInventoryItemAttributeList

    err, result <~ fetch do
        accountID: @account
        sku: item.Sku
    if err then return callback err

    debug "got api response"
    ###
    # Process API response
    result = result.GetInventoryItemAttributeListResult # ugh

    # Check if the message code is 0.
    #   If it's anything other than that, then we need to throw
    #   an error.
    if result.MessageCode is not 0
        return callback new Error "MessageCode is not 0, \
            but is #{result.MessageCode} with message: \
            #{result.Message}"

    data = result.ResultData.AttributeInfo

    ###
    # Create queue
    q = async.queue (attribute, done) ~>
        ###
        # Process queue
        err <~ @unpromise item.createAttribute attribute
        if err
            q.kill!
            return callback err
        done!

    q.drain = ~>
        callback null, item
    q.push data
