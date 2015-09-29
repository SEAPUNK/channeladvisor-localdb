require! <[
    ../queries
    async
    debug
]>

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

export get = (bindee) ->
    return start-fetching.bind(bindee)

var TIMER_ID
var TIMER_THIS
restart-timer = ->
    d = debug "CALDB:common:timer"
    if TIMER_THIS._stop
        d "NOOP: timer"
        return
    try
        clear-timeout TIMER_ID
    catch e
    TIMER_ID := set-timeout kill-caldb, 1000*60*10 # 10 minutes
    d "started or restarted timer"

    kill-caldb = ->
        if TIMER_THIS._stop
            d "NOOP: timer timeout"
            return
        d "TIMEOUT: No request has been received for a long time. Killing."
        TIMER_THIS.emit 'error', new ErrorInfo do
            fatal: yes
            error: new Error "CALDB fetch timeout; no response for 10 minutes"
            message: "CALDB fetch timeout; no response for 10 minutes"
            stage: "fetch"
        TIMER_THIS.stop "CALDB fetch timeout"

stop-timer = ->
    try
        clear-timeout TIMER_ID
    catch e

start-fetching = (type, page, current-page, callback) ->
    start-date = new Date
    fetch = @client.InventoryService.GetFilteredInventoryItemList
    TIMER_THIS := @

    fetch-next-page = (callback) ~>
        restart-timer!
        d = debug "CALDB:common:fetch-next-page"
        if @_stop
            d "STOP CALLED, QUITTING"
            return

        d "fetching page #{current-page}"

        d "inserting #{type}:progress"
        err <~ @unpromise @models.RunLog.create do
            updater: type
            event: 'progress'
            page-id: current-page
        if err
            stop-timer!
            return callback err

        @emit 'update-progress', new UpdateProgressInfo do
            type: type
            date: new Date
            date-started: start-date
            comment: ''
            current-page: current-page
            changed: @stats.changed
            deleted: @stats.deleted

        d "fetching next page"
        err, result <~ fetch page.next!.value
        if err
            stop-timer!
            return callback err
        if @_stop
            d "STOP CALLED, QUITTING @ PAGE LOAD"
            return
        d "fetched page"
        restart-timer!

        result = result.GetFilteredInventoryItemListResult

        if result.MessageCode is not 0
            stop-timer!
            return callback new Error "MessageCode is not 0, \
                but is #{result.MessageCode} with message: \
                #{result.Message}"

        data = result.{}ResultData.[]InventoryItemResponse

        if data.length is 0
            d "all items fetched"
            stop-timer!
            return callback "OKAY"

        q = async.queue do
            (item, done) ~>
                process-individual-item.call @, item, done
            100 # 100 items at a time
                #   because we don't want to wait
                #   about an hour for each page

        q.drain = ~>
            d "done processing items, \
                fetching next page"
            current-page++
            callback!

        items-left-to-fetch = data.length
        q.push data, (err, item) ~>
            restart-timer!
            if @_stop
                d "STOP: NO-OP AT ITEM DONE CALLBACK"
                return

            d = debug "CALDB:common:#{type}:queue"
            if err
                d "got error from an item during processing"
                q.kill!
                stop-timer!
                return callback err

            @stats.changed++

            d "item done fetching, #{--items-left-to-fetch} left"
            @emit 'item-update', new ItemUpdateInfo do
                type: type
                date: new Date

    async.forever do
        fetch-next-page,
        callback

process-individual-item = (item-data, callback) ->
    d = debug "CALDB:common:process-individual-item"
    if @_stop
        d "STOP: NOOP AT PROCESS-INDIVIDUAL-ITEM"
        return

    ###
    # Insert base data
    d "inserting data"
    err, item <~ create-item.call @, item-data
    if err then return callback err

    ###
    # Insert attribute data
    d "inserting attributes"
    err, item <~ set-item-attributes.call @, item
    if err then return callback err

    ###
    # Callback
    d "processed item"
    callback null, item

create-item = (item-data, callback) ->
    d = debug "CALDB:common:create-item"
    if @_stop
        d "STOP: NOOP AT CREATE-ITEM"
        return

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
        if @_stop
            d "STOP: NOOP AT CREATE-PRICE"
            return
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
        if @_stop
            d "STOP: NOOP AT CREATE-QUANTITY"
            return
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
    d = debug "CALDB:common:set-item-attributes"
    if @_stop
        d "STOP: NOOP AT SET-ITEM-ATTRIBUTES"
        return

    d "making api call"
    ###
    # Make the API call for the item
    fetch = @client.InventoryService.GetInventoryItemAttributeList

    restart-timer!
    err, result <~ fetch do
        accountID: @account
        sku: item.Sku
    if err then return callback err
    restart-timer!

    d "got api response"
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
    q = async.queue (attr, done) ~>
        if @_stop
            d "STOP: NOOP AT SET-ITEM-ATTRIBUTES.QUEUE"
            return
        _stop = (err) ->
            q.kill!
            return callback err

        ###
        # Process queue
        err, attributes <~ @unpromise item.getAttributes do
            where:
                Name: attr.Name
        if err then return _stop err

        attributes = attributes[0]
        if attributes.length is 1
            attribute = attributes[0]
            err <~ @unpromise attribute.update attr
            if err then return _stop err
            return done!
        else if not attributes.length
            err <~ @unpromise item.createAttribute attr
            if err then return _stop err
            return done!
        else
            return _stop new Error "Found more than one attribute for an item with the same name!"

    q.drain = ~>
        callback null, item
    q.push data
