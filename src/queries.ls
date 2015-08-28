export select-incomplete-catalog-run = """
    SELECT *
    FROM `RunLogs`
    WHERE
        `updater` = 'catalog'
    AND
        `event` = 'start'
    AND
        `date` > IFNULL((
            SELECT
                `date` AS `dt`
            FROM
                `RunLogs`
            WHERE
                `updater` = 'catalog'
            AND
                `event` = 'done'
            ORDER BY `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `date` DESC
    LIMIT 1
"""

export select-last-catalog-update-progress = """
    SELECT *
    FROM `RunLogs`
    WHERE
        `updater` = 'catalog'
    AND
        `event` = 'progress'
    AND
        `date` > IFNULL((
            SELECT
                `date` AS `dt`
            FROM
                `RunLogs`
            WHERE
                `updater` = 'catalog'
            AND
                `event` = 'done'
            ORDER BY `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `date` DESC
    LIMIT 1
"""

########################
### Unused queries below
########################

# Selects the last update checkpoint date.
export select-last-update-checkpoint-date = """
    SELECT `date`
    FROM `run_log`
    WHERE
        `updater` = 'updates'
    AND
        `event` = 'checkpoint'
    ORDER BY `date` DESC
    LIMIT 1
"""

export insert-run-log = """
    INSERT INTO `run_log` (
        `updater`,
        `event`,
        `date`,
        `comment`,
        `page_id`,
        `date_from`
    ) VALUES (
        ?,
        ?,
        ?,
        ?,
        ?,
        ?
    )
"""
# Selects the last page that is added to the catalog progress.
export select-catalog-resume-page = """
    SELECT `page_id`
    FROM `run_log`
    WHERE
        `updater` = 'catalog'
    AND
        `event` = 'progress'
    AND
        `date` > IFNULL((
            SELECT
                `date` AS `dt`
            FROM
                `run_log`
            WHERE
                `updater` = 'catalog'
            AND
                `event` = 'done'
            ORDER BY `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `date` DESC
    LIMIT 1
"""

export truncate-inventory = """
    TRUNCATE `inventory_items`;
    TRUNCATE `inventory_items_price`;
    TRUNCATE `inventory_items_quantity`;
"""

export replace-inventory-item = """
    REPLACE INTO inventory_items (
        `last_modified`,
        `Sku`,
        `Title`,
        `Subtitle`,
        `ShortDescription`,
        `Description`,
        `Weight`,
        `SupplierCode`,
        `WarehouseLocation`,
        `TaxProductCode`,
        `FlagStyle`,
        `FlagDescription`,
        `IsBlocked`,
        `BlockComment`,
        `ASIN`,
        `ISBN`,
        `UPC`,
        `MPN`,
        `EAN`,
        `Manufacturer`,
        `Brand`,
        `Condition`,
        `Warranty`,
        `ProductMargin`,
        `SupplierPO`,
        `HarmonizedCode`,
        `Height`,
        `Length`,
        `Width`,
        `Classification`
    ) VALUES (
        #{(['?'] * 30).join ", "}
    );
"""

export replace-inventory-quantity-data = """
    REPLACE INTO inventory_items_quantity (
        `item_sku`,
        `Available`,
        `OpenAllocated`,
        `OpenUnallocated`,
        `PendingCheckout`,
        `PendingPayment`,
        `PendingShipment`,
        `Total`,
        `OpenAllocatedPooled`,
        `OpenUnallocatedPooled`,
        `PendingCheckoutPooled`,
        `PendingPaymentPooled`,
        `PendingShipmentPooled`,
        `TotalPooled`
    ) VALUES (
        #{(['?'] * 14).join ", "}
    );
"""

export replace-inventory-price-data = """
    REPLACE INTO inventory_items_price (
        `item_sku`,
        `Cost`,
        `RetailPrice`,
        `StartingPrice`,
        `ReservePrice`,
        `TakeItPrice`,
        `SecondChanceOfferPrice`,
        `StorePrice`
    ) VALUES (
        #{(['?'] * 8).join ", "}
    );
"""