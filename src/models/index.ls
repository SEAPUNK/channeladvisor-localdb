require! <[
    ./inventory-item
    ./inventory-item-price
    ./inventory-item-quantity
    ./inventory-item-attribute
    ./run-log
]>

export define = ->
    export InventoryItem = inventory-item.define.call @
    export InventoryItemPrice = inventory-item-price.define.call @
    export InventoryItemQuantity = inventory-item-quantity.define.call @
    export InventoryItemAttribute = inventory-item-attribute.define.call @

    export RunLog = run-log.define.call @

    # relations
    InventoryItem.has-one InventoryItemQuantity, as: "Quantity"
    InventoryItem.has-one InventoryItemPrice, as: "Price"
    InventoryItem.has-many InventoryItemAttribute, as: "Attributes"