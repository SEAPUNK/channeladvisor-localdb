# Selects all rows from the run log, limit 5.
# Used for checking whether anything is even in the run log.
export select-limited-logs = """
    SELECT * FROM run_log LIMIT 5
"""

# Selects ID of the catalog run that hasn't been completed.
export select-incomplete-catalog-run = """
    SELECT `date`
    FROM `run_log`
    WHERE
        `updater` = 'catalog'
    AND
        `event` = 'start'
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
# Inserts a run log entry.
export insert-run-log = """
    INSERT INTO run_log (
        updater,
        event,
        date,
        comment,
        page_id,
        date_from
    ) VALUES (
        ?,
        ?,
        ?,
        ?,
        ?,
        ?
    )
"""

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
    TRUNCATE inventory_items;
    TRUNCATE inventory_items_distribution_centers;
"""