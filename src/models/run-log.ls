S = require 'sequelize'
require! '../queries'

export define = ->
    sequelize = @db
    @db.define 'RunLog',
        * updater: S.STRING(45)
          event: S.STRING(45)
          date:
            type: S.DATE()
            default-value: S.NOW
          comment:
            type: S.TEXT("long")
            default-value: ''
          page-id: S.INTEGER
          date-from: S.DATE()
        * class-methods:
            get-incomplete-catalog-run: (callback) ->
                promise = sequelize.query do
                    * queries.select-incomplete-catalog-run
                    * model: this
                promise.then do
                    (runlogs) ->
                        return callback null, runlogs[0]
                    (err) ->
                        return callback err
            get-last-catalog-update-progress: (callback) ->
                promise = sequelize.query do
                    * queries.select-last-catalog-update-progress
                    * model: this
                promise.then do
                    (runlogs) ->
                        return callback null, runlogs[0]
                    (err) ->
                        return callback err