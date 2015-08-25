# Selects all rows from the run log, limit 5.
# Used for checking whether anything is even in the run log.
export select-limited-logs = "
    SELECT * FROM run_log LIMIT 5
"

# Selects ID of the catalog run that hasn't been completed.
export select-incomplete-catalog-run = "
    SELECT `id`
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
        ), '1500-01-01');
"

