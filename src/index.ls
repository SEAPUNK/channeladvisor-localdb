require! <[
    winston mysql
    ./updaters ./queries ./models
]>

{EventEmitter} = require 'events'
Sequelize = require 'sequelize'
{
    UpdatesUpdateInfo
    CatalogUpdateInfo
    UpdateStartInfo
    UpdateStopInfo
    UpdateDoneInfo
    UpdateProgressInfo
    ErrorInfo
} = require './info-objects/'

# unpromise
unpromise = (promise, callback, spread = false) ->
    fnc = if spread then promise~spread else promise~then
    fnc do
        ->
            callback.apply @, [null].concat arguments
        ->
            callback ...

unpromise.spread = (promise, callback) ->
    unpromise.call @, promise, callback, true

class CALDB extends EventEmitter
    ({@account, @dburi, @client, @logger}) ->
        super!
        @initialized = false
        @set-logger!
        @reset-stats!
        @debugger = new Debugger do
            log: @logger~debug
            namespace: 'caldb'
        @debug = @debugger.debug
        @models = models
        @unpromise = unpromise

    # errout = "error out"
    errout: ->
        it.fatal ?= true
        it.error ?= new Error it.message
        @emit 'error', new ErrorInfo it

    set-logger: ->
        @logger ?= @make-dummy-logger!

    get-logger: -> @logger

    make-dummy-logger: ->
        new (winston.Logger) do
            transports: []

    reset-stats: ->
        @stats =
            added: 0
            changed: 0
            deleted: 0

    start: (manual, comment) ->
        debug = @debug.push "start"
        debug "called"

        if @initialized
            debug "already initialized, quitting"
            return

        <~ setTimeout
        <~ @run-checks
        <~ @prepare-updater
        @run-updater manual, comment

    run-checks: (callback) ->
        debug = @debug.push "run-checks"

        debug "called"

        # Initialize the database, then test the connection/authentication.
        debug "initializing sequelize, testing"
        @db = new Sequelize @dburi,
            logging: false

        err <~ @unpromise @db.authenticate!
        if err then return @errout do
            error: err
            message: "Could not connect to db"
            stage: "run-checks"

        # Then, check the client. Is it initialized?
        debug "check client init"
        if not @client.initialized then return @errout do
            message: "channeladvisor2 client \
                non-existent/non-initialized"
            stage: "run-checks"

        callback!

    prepare-updater: (callback) ->
        debug = @debug.push "prepare-updater"

        debug "called"

        # Prepare Sequelize.
        models.define.call @

        debug "defined models"

        # Sync database.
        err <~ @unpromise @db.sync force: false

        debug "db sync done"
        if err then return @errout do
            error: err
            message: "could not sync sequelize to db"
            stage: "prepare-updater"

        callback!

    catalog-done: ->
        @run-updater no, ''

    updates-done: ->
        set-timeout do
            ~>
                @run-updater no, ''
            60*60*1000 # one hour

    run-updater: (manual, comment) ->
        debug = @debug.push "run-updater"

        debug "called"

        # Check to see if we're doing a "manual" catalog update.
        if manual is yes
            debug "is forced, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment, , manual

        # Check if there is anything in the run_log.
        #   If there isn't, then run catalog, since this is
        #   A fresh installation.
        err, count <~ @unpromise @models.RunLog.count!
        if err then return @errout do
            error: err
            message: "could not run database query, \
                at @models.RunLog.count()"
            stage: "determine-updater"
        if count.0 is 0
            debug "nothing in the run log, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment

        # Now, check if there has been an incomplete catalog update.
        #   If there is an item, then run catalog.
        err, runlog <~ @models.RunLog.get-incomplete-catalog-run
        if err
            return @errout do
                error: err
                message: "could not run database query, \
                    at run-updater,select-incomplete-catalog-run"
                stage: "determine-updater"
        if runlog.length is not 0 and runlog[0].date
            debug "incomplete catalog update, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment, runlog[0].date

        # Else, we can just run 'updates'.
        return set-timeout ~>
            debug "all checks seem to have passed, calling updates"
            updaters.updates.call @, comment

module.exports = CALDB

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