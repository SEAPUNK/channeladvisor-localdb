info objects
===

---

<a name="update-start">
###`UpdateStartInfo`

* `type`: Type of updater that is running. Either 'catalog' or 'updates'.
* `date`: Date the update started.
* `info`: An instance of `UpdatesUpdateInfo` or `CatalogUpdateInfo`, depending on the type.
* `comment`: Any user-set or automatically set comment about the update.

---

<a name="update-stop">

---

<a name="update-done">

---

<a name="update-progress">

---

<a name="item-update">

---

<a name="error"></a>
###`ErrorInfo`

* `error`: Error object that pertains to the error event, if any
* `message`: Error message
* `stage`: Stage of execution when the error was called
* `fatal`: If the error is going to prevent further execution of the updater

---

class UpdateContinueInfo
        @date-to
        @page

class UpdateStatisticsInfo
        @changed
        @deleted

class GenericUpdateInfo extends UpdateContinueInfo
        @date-from

export class ItemUpdateInfo
        @type
        @date


export class UpdatesUpdateInfo extends GenericUpdateInfo

export class CatalogUpdateInfo extends GenericUpdateInfo


export class UpdateStopInfo extends UpdateStatisticsInfo
        @type
        @date
        @date-started
        @stop-reason
        @comment

export class UpdateDoneInfo extends UpdateStatisticsInfo
        @type
        @date
        @comment

export class UpdateProgressInfo extends UpdateStatisticsInfo
        @type
        @date
        @date-started
        @comment
        @current-page
        @duration = @date - @date-started

export class ErrorInfo
        @error
        @message
        @stage
        @fata