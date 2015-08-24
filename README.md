channeladvisor-localdb
===

library to create a local database of inventory items from channeladvisor

install
---

`npm install channeladvisor-localdb`

use
---

*examples are written in [livescript](https://livescript.net/)*

```livescript

require! <[ util ]>
require! 'channeladvisor-localdb':CALDB

ldb = new CALDB do
    db:
        host: 'localhost'
        user: 'ca_admin'
        password: 'ca_password'
        database: 'channeladvisor'
    client: client
    logger: logger

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
    * `db`: [`node-mysql`](https://github.com/felixge/node-mysql/) createConnection options
    * `client`: instance of the initialized [`node-channeladvisor2`](https://github.com/SEAPUNK/noed-channeladvisor2) client
    * `logger`: a [`winston`](https://github.com/winstonjs/winston) logger instance, for if you want to log

###`CALDB events`

CALDB instances are also instances of the [EventEmitter](https://nodejs.org/api/events.html#events_class_events_eventemitter) class.

List of events are [here](#events)

###`CALDB#start()`

Starts DB updater. Async function, runs in the background.

###`CALDB#stop(callback)`

Stops DB updater.

* `callback(err)`: Called when done stopping. `err` is not null if it didn't cleanly stop.


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