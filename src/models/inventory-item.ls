S = require 'sequelize'

export define = ->
    @db.define 'InventoryItem',
        Sku:
            type: S.STRING(50)
            unique: true
        Title: S.STRING(255)
        Subtitle: S.STRING(100)
        ShortDescription: S.STRING(1000)
        Description: S.TEXT('long')
        Weight: S.FLOAT.UNSIGNED
        SupplierCode: S.STRING(50)
        WarehouseLocation: S.STRING(80)
        TaxProductCode: S.STRING(25)
        FlagStyle: S.STRING(50)
        FlagDescription: S.STRING(80)
        IsBlocked: S.BOOLEAN
        BlockComment: S.STRING(80)
        ASIN: S.STRING(14)
        ISBN: S.STRING(20)
        UPC: S.STRING(20)
        EAN: S.STRING(20)
        MPN: S.STRING(50)
        Manufacturer: S.STRING(255)
        Brand: S.STRING(150)
        Condition: S.STRING(50)
        Warranty: S.STRING(255)
        ProductMargin: S.FLOAT
        SupplierPO: S.STRING(255)
        HarmonizedCode: S.STRING(20)
        Height: S.FLOAT.UNSIGNED
        Length: S.FLOAT.UNSIGNED
        Width: S.FLOAT.UNSIGNED
        Classification: S.STRING(35)
        MetaDescription: S.STRING(200)