S = require 'sequelize'

export define = ->
    @db.define 'InventoryItemPrice',
        * Cost: S.FLOAT
          RetailPrice: S.FLOAT
          StartingPrice: S.FLOAT
          ReservePrice: S.FLOAT
          TakeItPrice: S.FLOAT
          SecondChanceOfferPrice: S.FLOAT
          StorePrice: S.FLOAT