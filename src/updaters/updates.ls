require! <[
    ./queries
]>

{
    UpdatesUpdateInfo
    CatalogUpdateInfo
    UpdateStartInfo
    UpdateStopInfo
    UpdateDoneInfo
    UpdateProgressInfo
    ErrorInfo
} = require './info-objects/'

module.exports = (root) ->
    db = root.db
    emit = root.emit

    var date-to-fetch-from
    var date-to-fetch-to
    var start-date
    current-page = 1

    # Get the date from the last update checkpoint.
    err, rows <- db.query queries.select-last-update-checkpoint-date
    if err
        return emit 'error', new ErrorInfo do
            error: err
            message: "could not run database query, \
                at updater.updates,select-last-update-checkpoint-date"
            stage: "updates:pre-run-checks"
            fatal: true
    if rows.length is 0
        return emit 'error', new ErrorInfo do
            error: new Error "no update checkpoints, should never happen"
            message: "no update checkpoints for the updates updater! \
                this should never happen."
            stage: "updates:pre-run-checks"
            fatal: true

    date-to-fetch-from := rows[0].date
    date-to-fetch-to := new Date # TODO: Get the last update date.
    start-date := new Date

    # Insert the update:start run log entry.
    err <- db.query queries.insert-run-log, [
        'updates'
        'start',
        start-date,
        null,
        null,
        date-to-fetch-from
    ]

    if err
        return emit 'error', new ErrorInfo do
            error: err
            message: "could not run database query, \
                at updater.updates,insert-run-log"
            stage: "updates:start-run"
            fatal: true

    # Emit the update-start event, then start fetching.
    emit 'update-start', new UpdateStartInfo do
        type: 'updates'
        date: start-date
        info: new UpdatesUpdateInfo do
            date-from: date-to-fetch-from
            date-to: date-to-fetch-to
            page: current-page
        comment: ""