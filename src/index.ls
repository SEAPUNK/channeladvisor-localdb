require! <[
    winston mysql
    ./updaters ./queries
]>

{EventEmitter} = require 'events'

{
    UpdatesUpdateInfo
    CatalogUpdateInfo
    UpdateStartInfo
    UpdateStopInfo
    UpdateDoneInfo
    UpdateProgressInfo
    ErrorInfo
} = require './info-objects/'

class CALDB extends EventEmitter
    ({@dbopts, @client, @logger}) ->
        super!
        @set-logger!

    set-logger: ->
        @logger ?= @make-dummy-logger!

    get-logger: -> @logger

    make-dummy-logger: ->
        new (winston.Logger) do
            transports: []

    start: (manual, comment) ->
        set-timeout ~>
            @start-updater manual, comment

    start-updater: (manual, commment) ->
        if not @initialized
            @run-checks ~>
                @run-updater manual, comment

    run-checks: (callback) ->
        # First, check if the database connection will work
        @db = mysql.create-connection @dbopts
        err <~ @db.connect
        if err
            return @emit 'error', new ErrorInfo do
                error: err
                message: "Could not connect to db"
                stage: "pre-update-checks"
                fatal: true

        # Try a database query that should work.
        #   In this case, select items from the run log.
        err <~ @db.query "SELECT * FROM run_log LIMIT 10"
        if err
            return @emit 'error', new ErrorInfo do
                error: err
                message: "Could not run a test query on DB; \
                    has it been initialized?"
                stage: "pre-update-checks"
                fatal: true

        # Then, check the client. Is it initialized?
        #   We're going to check by seeing if
        #   a test SOAP method is available.
        if not @client?.AdminService?.Ping?
            return @emit 'error', new ErrorInfo do
                error: new Error "channeladvisor2 client \
                    non-existent/non-initialized"
                message: "Client is not initialized"
                stage: "pre-update-checks"
                fatal: true


    run-updater: (manual, comment) ->
        # First, check to see what kind of update
        #   we need to run.

        # Check to see if we're doing a "manual" catalog update.
        if manual is true
            return set-timeout ~>
                updaters.catalog @

        # Check if there is anything in the run_log.
        #   If there isn't, then run catalog, since this is
        #   A fresh installation.
        err, rows <~ @db.query queries.select-limited-logs
        if err
            return @emit 'error', new ErrorInfo do
                error: err
                message: "could not run database query, \
                    at run-updater,select-limited-logs"
                stage: "determine-updater"
                fatal: true
        if rows.length is 0
            return set-timeout ~>
                updaters.catalog @

        # Now, check if there has been an incomplete catalog update.
        #   If there is an item, then run catalog.
        err, rows <~ @db.query queries.select-incomplete-catalog-run
        if err
            return @emit 'error', new ErrorInfo do
                error: err
                message: "could not run database query, \
                    at run-updater,select-incomplete-catalog-run"
                stage: "determine-updater"
                fatal: true
        if rows.length is not 0
            return set-timeout ~>
                updaters.catalog @

        # Else, we can just run 'updates'.
        return set-timeout ~>
            updater.updates @

module.exports = CALDB