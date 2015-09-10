channeladvisor-localdb
===

library to create a local database of inventory items from channeladvisor

install
---

`npm install channeladvisor-localdb`

limitations
---

due to laziness and not enough time, these InventoryItemResponse fields currently
are not implemented into the database:

* DistributionCenterList
* VariationInfo
* StoreInfo
* ImageList
* MetaDescription

and, there are a bunch of things i should do to it (getters, setters, overrides, etc), but i don't quite have the time to do it right now; if you want it so bad, open up a pull request?

use
---

*examples are written in [livescript](https://livescript.net/)*

```livescript

require! <[ util ]>
require! 'channeladvisor-localdb':CALDB

ldb = new CALDB do
    dburi: "mysql://ca_admin:ca_password@localhost/channeladvisor"
    client: client
    logger: logger
    account: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

ldb.on 'error', (info) ->
    console.log util.inspect info
    throw info.error

ldb.on 'update-progress', (info) ->
    console.log util.inspect info

ldb.start!

```

###`CALDB(opts)`

Creates new instance of the ChannelAdvisor localDB

* `opts`: `object`
    * `dburi`: A database URI that [`sequelize`](https://github.com/sequelize/sequelize) will accept
    * `client`: instance of the initialized [`channeladvisor2`](https://github.com/SEAPUNK/channeladvisor2) client
    * `logger`: a [`winston`](https://github.com/winstonjs/winston) logger instance, for if you want to log
    * `account`: the account ID for the database (format is `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

###`CALDB events`

CALDB instances are also instances of the [EventEmitter](https://nodejs.org/api/events.html#events_class_events_eventemitter) class.

List of events are [here](#events)

###`CALDB#start(manual, comment)`

Starts DB updater. Async function, runs in the background.

* `manual`: Whether to force a catalog update. ***This truncates the existing inventory database!***
* `comment`: Meta comment to store in the run log

<a name="events"></a>
###Events

---

`update-start -> (info)`

Called when a database update has started

* `info`: [UpdateStartInfo](docs/info-objects.md#update-start) instance

---

`update-stop -> (info)`

Called whenever a database update is forcefully stopped

* `info`: [UpdateStopInfo](docs/info-objects.md#update-stop) instance

---

`update-done -> (info)`

Called when a database update has completed

* `info`: [UpdateDoneInfo](docs/info-objects.md#update-done) instance

---

`update-progress -> (info)`

Called when there's progress in the database update.

* `info`: [ProgressInfo](docs/info-objects.md#progress) instance

---

`error -> (info)`

Called whenever there's an error, may it be with updating or anything else.

* `info`: [ErrorInfo](docs/info-objects.md#error) instance

---


*side note: the code is doing a lot of copy-pasting, which is obviously bad;
i will eventually do something about that, but until then...*
