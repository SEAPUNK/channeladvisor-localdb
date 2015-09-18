channeladvisor-localdb
===

library to create a local database of inventory items from channeladvisor

**warning:** could use a lot of memory (~1GB), depending on how complex or
full of data your inventory items are. i suggest that you run this library in
its [server wrapper](https://github.com/seapunk/caldb-d)

install
---

`npm install channeladvisor-localdb`

limitations
---

these InventoryItemResponse fields currently are currently not implemented
into this library:

* DistributionCenterList
* VariationInfo
* StoreInfo
* ImageList
* MetaDescription

use
---

```javascript

var CALDB = require("channeladvisor-localdb")

var ldb = new CALDB({
    dburi: "mysql://ca_admin:ca_password@localhost/channeladvisor",
    client: client, //initialized channeladvisor2 client
    account: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
})

ldb.on('error', function(info){
    console.log(util.inspect(info))
    throw info.error
})

ldb.on('update-progress', function(info){
    console.log(util.inspect(info))
})

ldb.start()

```

###`CALDB(opts)`

Creates new instance of the ChannelAdvisor localDB

* `opts`: `object`
    * `dburi`: A database URI that [`sequelize`](https://github.com/sequelize/sequelize) will accept
    * `client`: instance of the initialized [`channeladvisor2`](https://github.com/SEAPUNK/channeladvisor2) client
    * `account`: the account ID for the database (format is `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

###`CALDB#start(manual, comment)`

Starts DB updater. Async function, runs in the background.

* `manual`: Whether to force a catalog update. ***This truncates the existing inventory database!***
* `comment`: Meta comment to store in the run log

###`CALDB#expose-models()`

Returns the Sequelize models that CALDB is using.

###`CALDB#expose-sequelize()`

Returns the Sequelize instance that CALDB is using.

###`CALDB events`

CALDB instances are also instances of the [EventEmitter](https://nodejs.org/api/events.html#events_class_events_eventemitter) class.

List of events are [here](#events)


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

* `info`: [ProgressInfo](docs/info-objects.md#update-progress) instance

---

`item-update -> (info)`

Called when an item has been successfully pushed into the database.

* `info`: [ItemUpdateInfo](docs/info-objects.md#item-update) instance

---

`error -> (info)`

Called whenever there's an error, may it be with updating or anything else.

* `info`: [ErrorInfo](docs/info-objects.md#error) instance

---