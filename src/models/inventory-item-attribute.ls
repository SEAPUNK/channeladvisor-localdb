S = require 'sequelize'

export define = ->
    @db.define 'InventoryItemAttribute',
        * Name: S.STRING(32)
          Value: S.TEXT('long')