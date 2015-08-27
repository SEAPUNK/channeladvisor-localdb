require! <[
    winston mysql
    ./updaters ./queries
]>

# TODO: for queries, shall there be a hard limit to run FROM catalog reset?
# TODO: clean up code; use sequelize?
# TODO: unless we're using sequelize, we need to add set* functions.
# TODO: a getter for the items

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


Debugger = ({@log, @namespace, @previous = null}) !->
    this$ = this

    this.debug = (message) ->
        this$.log this$.namespace + ": " + message

    this.debug.pop = ->
        if not this$.previous?
            throw new Error "no more namespaces to revert to"
        return this$.previous.debug

    this.debug.push = (subnamespace) ->
        dbg = new Debugger do
            log: this$.log
            namespace: "#{this$.namespace}/#{subnamespace}"
            previous: this$
        return dbg.debug

class CALDB extends EventEmitter
    ({@account, @dbopts, @client, @logger}) ->
        super!
        @set-logger!
        @items-added = 0
        @items-changed = 0
        @items-deleted = 0

        @debugger = new Debugger do
            log: @logger~debug
            namespace: 'caldb'
        @debug = @debugger.debug

    set-logger: ->
        @logger ?= @make-dummy-logger!

    get-logger: -> @logger

    make-dummy-logger: ->
        new (winston.Logger) do
            transports: []


    #######################################################################


    start: (manual, comment) ->
        debug = @debug.push "start"

        debug "called"
        set-timeout ~>
            @start-updater manual, comment

    start-updater: (manual, comment) ->
        debug = @debug.push "start-updater"

        debug "called"
        if not @initialized
            @run-checks ~>
                @run-updater manual, comment

    run-checks: (callback) ->
        debug = @debug.push "run-checks"

        debug "called"
        # First, check if the database connection will work
        @dbopts.multiple-statements = true
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
        debug "try db query"
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
        debug "check client init"
        if not @client?.AdminService?.Ping?
            return @emit 'error', new ErrorInfo do
                error: new Error "channeladvisor2 client \
                    non-existent/non-initialized"
                message: "Client is not initialized"
                stage: "pre-update-checks"
                fatal: true

        callback!

    reset-counters: ->
        @items-added := 0
        @items-changed := 0
        @items-deleted := 0

    run-updater: (manual, comment) ->
        debug = @debug.push "run-updater"

        debug "called"
        # First, check to see what kind of update
        #   we need to run.

        # Check to see if we're doing a "manual" catalog update.
        if manual is yes
            debug "is forced, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment, , manual

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
            debug "nothing in the run log, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment

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
            debug "incomplete catalog update, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment, rows[0].date

        # Else, we can just run 'updates'.
        return set-timeout ~>
            debug "all checks seem to have passed, calling updates"
            updater.updates.call @, comment

module.exports = CALDB