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
            ORDER BY `id` DESC, `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `id` DESC, `date` DESC
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
            ORDER BY `id` DESC, `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `id` DESC, `date` DESC
    LIMIT 1
"""

export select-last-updates-checkpoint = """
    SELECT *
    FROM `RunLogs`
    WHERE
        `updater` = 'updates'
    AND
        `event` = 'checkpoint'
    ORDER BY `id` DESC, `date` DESC
    LIMIT 1
"""

export select-last-incomplete-updates-progress = """
    SELECT *
    FROM `RunLogs`
    WHERE
        `updater` = 'updates'
    AND
        `event` = 'progress'
    AND
        `date` > IFNULL((
            SELECT
                `date` AS `dt`
            FROM
                `RunLogs`
            WHERE
                `updater` = 'updates'
            AND
                `event` = 'done'
            ORDER BY `id` DESC, `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `id` DESC, `date` DESC
    LIMIT 1
"""

export select-last-incomplete-updates-start = """
    SELECT *
    FROM `RunLogs`
    WHERE
        `updater` = 'updates'
    AND
        `event` = 'progress'
    AND
        `date` > IFNULL((
            SELECT
                `date` AS `dt`
            FROM
                `RunLogs`
            WHERE
                `updater` = 'updates'
            AND
                `event` = 'done'
            ORDER BY `id` DESC, `date` DESC
            LIMIT 1
        ), '1500-01-01')
    ORDER BY `id` DESC, `date` DESC
    LIMIT 1
"""