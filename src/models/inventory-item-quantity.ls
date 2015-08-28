S = require 'sequelize'

export define = ->
    @db.define 'InventoryItemQuantity',
        * Available: S.INTEGER.UNSIGNED
          OpenAllocated: S.INTEGER.UNSIGNED
          OpenUnallocated: S.INTEGER.UNSIGNED
          PendingCheckout: S.INTEGER.UNSIGNED
          PendingPayment: S.INTEGER.UNSIGNED
          PendingShipment: S.INTEGER.UNSIGNED
          Total: S.INTEGER.UNSIGNED
          OpenAllocatedPooled: S.INTEGER.UNSIGNED
          OpenUnallocatedPooled: S.INTEGER.UNSIGNED
          PendingCheckoutPooled: S.INTEGER.UNSIGNED
          PendingPaymentPooled: S.INTEGER.UNSIGNED
          PendingShipmentPooled: S.INTEGER.UNSIGNED
          TotalPooled: S.INTEGER.UNSIGNED