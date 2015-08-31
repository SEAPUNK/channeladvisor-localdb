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

module.exports = (comment) ->
    debug = @debug.push "updates"
    debug "start"

    ###
    # Reset stats
    @reset-stats!

    ###
    # Variables
    fetch = @client.InventoryService.GetFilteredInventoryItemList

    ###
    # Fetch checkpoint
    debug "RunLog.get-last-updates-checkpoint"
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

    ###
    # Fetch resume data, pt.1
    debug "RunLog.get-last-incomplete-updates-start"
    err, runlog <~ @models.RunLog.get-last-incomplete-updates-start
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at updates:RunLog.get-last-incomplete-updates-start"
            stage: "updates:pre-run-checks"

    if runlog.length is not 0
        date-to-fetch-to = runlog[0].date

    ###
    # Fetch resume data, pt.2
    debug "RunLog.get-last-incomplete-updates-progress"
    err, runlog <~ @models.RunLog.get-last-incomplete-updates-progress
    if err
        return @errout do
            error: err
            message: "could not run database query, \
                at updates:RunLog.get-last-incomplete-updates-progress"
            stage: "updates:pre-run-checks"

    if date-to-fetch-to
    and runlog.length is not 0
        current-page = runlog[0].page-id

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
        debug "continuing updates, #{date-to-fetch-to}"
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
            debug "insert updates:start"
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
            next!

        ###
        # Emit update-start
        (next) ~>
            # emit the update-start event, then start fetching.
            debug "emit update-start"
            @emit 'update-start', new UpdateStartInfo do
                type: 'updates'
                date: start-date
                info: new UpdatesUpdateInfo do
                    date-from: date-to-fetch-from
                    date-to: date-to-fetch-to
                    page: current-page
                comment: comment
            next!

        ###
        # Pages generator
        (next) ~>
            pages = !~>*
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
                    # Insert updates:progress
                    debug "inserting updates:progress"
                    err <~ @unpromise @models.RunLog.create do
                        updater: 'updates'
                        event: 'progress'
                        page-id: current-page

                    if err then return callback err

                    ###
                    # Emit update-progress
                    @emit 'update-progress', new UpdateProgressInfo do
                        type: 'updates'
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
                        debug = (@debug.push "updates").push "queue"
                        if err
                            debug "got error from an item during processing"
                            q.kill!
                            return callback err

                        ###
                        # Up the counter
                        @stats.changed++

                        ###
                        # Get the item again,
                        #   but with associations eager-loaded
                        err, item <~ @unpromise @models.InventoryItem.findOne do
                            where:
                                Sku: item.Sku
                            include: [
                                * model: @models.InventoryItemAttribute
                                  as: "Attributes"
                                * model: @models.InventoryItemPrice
                                  as: "Price"
                                * model: @models.InventoryItemQuantity
                                  as: "Quantity"
                            ]

                        if err
                            debug "could not re-fetch the item"
                            q.kill!
                            return callback err

                        ###
                        # Emit item-update
                        debug "item done fetching, #{--items-left-to-fetch} left"
                        @emit 'item-update', new ItemUpdateInfo do
                            type: 'updates'
                            date: new Date
                            item: item

                (err) ~>
                    if err is not "OKAY"
                        debug "err is NOT 'OKAY'"
                        return @emit 'error', new ErrorInfo do
                            error: err
                            message: "could not process/query items"
                            stage: "updates:get-next-page"
                            fatal: true

                    debug "cleaning up; \
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

                    @emit 'update-done', new UpdateDoneInfo do
                        type: 'updates'
                        date: new Date
                        comment: comment
                        changed: @stats.changed
                        deleted: @stats.deleted

                    debug "selecting 'updates' updater"
                    @updates-done!

    ], (err) ~>
        throw err


process-individual-item = (item-data, callback) ->
    debug = (@debug.push "updates").push "process-individual-item"

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

    ###
    # Create InventoryItemPrice association
    err <~ @unpromise item.createPrice price-data
    if err then return callback err

    ###
    # Create InventoryItemQuantity association
    err <~ @unpromise item.createQuantity quantity-data
    if err then return callback err

    return callback null, item

set-item-attributes = (item, callback) ->
    debug = (@debug.push "updates").push "set-item-attributes"

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