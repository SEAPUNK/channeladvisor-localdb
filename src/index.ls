require! <[
    mysql debug
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
    d = debug 'CALDB:unpromise'
    d "unpromising function (spread: #{spread})"
    fnc = if spread then promise~spread else promise~then
    fnc do
        ->
            d "unpromise call success"
            callback.apply @, [null].concat arguments
        ->
            d "unpromise call fail"
            callback ...

unpromise.spread = (promise, callback) ->
    unpromise.call @, promise, callback, true

class CALDB extends EventEmitter
    ({@account, @dburi, @client, @logger}) ->
        d = debug 'CALDB:construct'
        d 'constructing'
        super!
        @initialized = false
        @reset-stats!
        @models = models
        @unpromise = unpromise

    # errout = "error out"
    errout: ->
        d = debug "CALDB:errout"
        d 'sending error'
        it.fatal ?= true
        it.error ?= new Error it.message
        @emit 'error', new ErrorInfo it

    reset-stats: ->
        d = debug "CALDB:reset-stats"
        d 'resetting stats'
        @stats =
            added: 0
            changed: 0
            deleted: 0

    start: (manual, comment, noop) ->
        d = debug 'CALDB:start'
        d 'starting'

        if @initialized
            d "already initialized, quitting"
            return
        @initialized = yes

        <~ setTimeout
        <~ @run-checks
        <~ @prepare-updater
        if not noop
            d 'not a noop, running updater'
            @run-updater manual, comment
        else
            d 'noop, emitting ready'
            @emit 'ready'

    run-checks: (callback) ->
        d = debug 'CALDB:run-checks'

        # Initialize the database, then test the connection/authentication.
        d "initializing sequelize"
        @db = new Sequelize @dburi,
            logging: false

        d "authenticating to DB"
        err <~ @unpromise @db.authenticate!
        if err then return @errout do
            error: err
            message: "Could not connect to db"
            stage: "run-checks"

        # Then, check the client. Is it initialized?
        d "check client init"
        if not @client.initialized then return @errout do
            message: "channeladvisor2 client \
                non-existent/non-initialized"
            stage: "run-checks"

        callback!

    prepare-updater: (callback) ->
        d = debug "CALDB:prepare-updater"

        # Prepare Sequelize.
        d "defining models"
        models.define.call @

        # Sync database.
        d "syncing database"
        err <~ @unpromise @db.sync force: false
        if err then return @errout do
            error: err
            message: "could not sync sequelize to db"
            stage: "prepare-updater"

        callback!

    catalog-done: ->
        d = debug "CALDB:catalog-done"
        d "catalog updater done, running updates updater"
        @run-updater no, ''

    updates-done: (immediate) ->
        d = debug "CALDB:updates-done"
        d "updates updater done, requeuing (immedate: #{immediate})"
        timer = 1000*60*10 # 10 minutes
        if immediate then timer = 0

        set-timeout do
            ~>
                d "starting updates updater"
                @run-updater no, ''
            timer

    run-updater: (manual, comment) ->
        d = debug "CALDB:run-updater"

        d "determining updater"

        # Check to see if we're doing a "manual" catalog update.
        if manual is yes
            d "is forced, calling catalog"
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
        if count[0] is 0
            d "nothing in the run log, calling catalog"
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
            d "incomplete catalog update, calling catalog"
            return set-timeout ~>
                updaters.catalog.call @, comment, runlog[0].date

        # Else, we can just run 'updates'.
        return set-timeout ~>
            d "all checks seem to have passed, calling updates"
            updaters.updates.call @, comment

    expose-models: ->
        return @models

    expose-sequelize: ->
        return @db

    stop: ->
        @_stop = yes

module.exports = CALDB