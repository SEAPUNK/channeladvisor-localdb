require! <[ winston mysql ]>

{EventEmitter} = require 'events'

{
    UpdateStartInfo
    UpdateStopInfo
    UpdateDoneInfo
    ProgressInfo
    ErrorInfo
} = require './info-objects/'

class CALDB extends EventEmitter
    ({@dbopts, @client, @logger}) ->
        @set-logger!

    set-logger: ->
        @logger ?= @make-dummy-logger!

    get-logger: -> @logger

    make-dummy-logger: ->
        new (winston.Logger) do
            transports: []

    start: ->
        set-timeout @start-updater

    start-updater: ->
        if not @initialized
            @run-checks @run-updater

    run-checks: (callback) ->
        # First, check if the database connection will work
        @dbconn = mysql.create-connection @dbopts
        err <~ connection.connect
        if err
            @emit 'error', new ErrorInfo do
                error: err
                message: "Could not connect to db"
                stage: "pre-update-checks"

    run-updater: ->
        console.log 'updater has started'

module.exports = CALDB