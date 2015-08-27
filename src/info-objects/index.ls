/*
    See docs/info-object.md for info
*/

# Order matters with class definitions:
#   base classes
#   non-exported extended classes
#   exported extended classes

# base classes
class UpdateContinueInfo
    ({
        @date-to
        @page
    }) ->
        # no superclass

class UpdateStatisticsInfo
    ({
        @added
        @changed
        @deleted
    }) ->
        @processed = @added + @changed + @deleted

# non-exported extended classes
class GenericUpdateInfo extends UpdateContinueInfo
    ({
        @date-from
    }) ->
        super ...

# exported extended classes
export class UpdatesUpdateInfo extends GenericUpdateInfo
    ->
        super ...

export class CatalogUpdateInfo extends GenericUpdateInfo
    ->
        super ...

export class UpdateStartInfo
    ({
        @type
        @date
        @info
        @comment
    }) ->
        # no superclass

export class UpdateStopInfo extends UpdateStatisticsInfo
    ({
        @type
        @date
        @date-started

        @stop-reason
        @comment
    }) ->
        super ...

export class UpdateDoneInfo extends UpdateStatisticsInfo
    ({
        @type
        @date
        @info
        @comment
    }) ->
        super ...

export class UpdateProgressInfo extends UpdateStatisticsInfo
    ({
        @type
        @date
        @date-started
        @comment
    }) ->
        @duration = @date-started - @date
        super ...

export class ErrorInfo
    ({
        @error
        @msg
        @stage
        @fatal
        @comment
    }) ->
        # no superclass