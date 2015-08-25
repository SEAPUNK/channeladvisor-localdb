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
                fatal: true
            return

        # Try a database query that should work.
        #   In this case, select items from the run log.
        err <~ connection.query "SELECT * FROM run_log LIMIT 10"
        if err
            @emit 'error', new ErrorInfo do
                error: err
                message: "Could not run a test query on DB; \
                    has it been initialized?"
                stage: "pre-update-checks"
                fatal: true

        # Then, check the client. Is it initialized?
        #   We're going to check by seeing if
        #   a test SOAP method is available.
        if not @client?.AdminService?.Ping?
            @emit 'error', new ErrorInfo do
                error: new Error "channeladvisor2 client \
                    non-existent/non-initialized"
                message: "Client is not initialized"
                stage: "pre-update-checks"
                fatal: true
            return


    run-updater: ->


module.exports = CALDB