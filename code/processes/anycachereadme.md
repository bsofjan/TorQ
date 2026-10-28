AnyCache README

AnyCache is a caching system meant to be deployed alongside an existing kdb+/q setup. Anycache runs queries on a schedule (static mode) or on request (request mode), saves the results to disk, and lets any process or KX Dashboards read them.

## Architecture

Setter builds on a timer (when in static mode) or when triggered (when in request mode). Setter takes in configuration from the `cacheconfig.json`, and queries the gateway to get the data it builds its caches from. Every main cache can be made up of multiple component caches, which can be specified in the `cacheconfig.json`.

```
  feed -> stp -> rdb ------------+
           |                     |
           +-> wdb -> hdb -------+
                                 |
                              gateway        joins hdb and rdb results
                                 ^
                                 | queries
  cacheconfig.json --------->  setter        builds on a timer (static) or when triggered (request)
                                 |
                                 | writes builds, reads requests
                                 v
  <cacherootdir>/<cachename>/
    <cachename>_<timestamp>/     one build: start and end times, one folder per component cache
      cache1/data                anymap file(s)
    <cachename>                  symlink to the newest build (static mode)
    asynccache_<timestamp>/args  a cache request (request mode)

  KX Dashboards ---> setter      .anycache.setter.getcache / .anycache.setter.cachebuilds
```

## Processes

| Process | Role in AnyCache |
|---|---|
| `setter` | Builds the caches and writes them to disk. Reads `cacheconfig.json`, sends its queries to the gateway, and serves the cache to the dashboard. Code: `code/processes/setter.q`. |
| `gateway` | Receives and runs setter's queries and returns the results. |
| TorQ processes | Loads `code/common/getter.q`, which allows it to read static builds and write cache requests. |
| KX Dashboard | A separate q process that connects to setter and polls its read API. |

## Install

To install, run `demosetup.sh`.

It pulls the TorQ Finance Starter Pack, then lays TorQ on top with the anycache system.

demosetup script:
```bash
mkdir "anycachedemo"
cd "anycachedemo"
git clone "https://github.com/DataIntellectTech/TorQ-Finance-Starter-Pack" "."
mkdir "temp"
cd "temp"
git clone -b "anycache" "https://github.com/bsofjan/TorQ.git" "."
cp -a "." ".."
cd ".."
rm -rf "temp"
rm -rf ".git"
```

Then in `setenv.sh` set `KDBX` to your KDB-X (5.0) binary and, if needed, `KDBBASEPORT`, and start everything:

```bash
./torq.sh start all
./torq.sh summary
```

`setter1` starts with the rest, on port `KDBBASEPORT+24`.

## Configure

Setter reads `cacheconfig.json`.

| Field | Meaning |
|---|---|
| `cacherootdir` | Folder the caches are written to |
| `cachename` | Name of the cache, used for folder names |
| `asyncprocessname` | Folder prefix for cache requests |
| `componentcaches.<name>.staticmode` | Query run for that component cache in static mode |
| `componentcaches.<name>.datasource` | Where static mode queries run eg `rdb` |
| `setter.mode` | `request` for request mode, anything else (eg `static`) for static mode |
| `setter.interval` | Static mode: time between builds, eg `0D00:01` |
| `setter.cachestokeep` | Request mode: builds and requests kept on disk |
| `setter.maxresultmb` | Largest result saved, in MB |
| `setter.maxdatespan` | Request mode: most days a query can cover |

Example `cacheconfig.json`:

```json
{
    "cacherootdir": "/path/to/anycachedata",
    "cachename": "myfirstcache",
    "asyncprocessname": "asynccache",
    "componentcaches":{
        "cache1": {
            "analytic": "analytic1",
            "datasource": "rdb",
            "staticmode": "select by sym from trade"
        },
        "cache2": {
            "analytic": "analytic2",
            "datasource": "rdb",
            "staticmode": "select by sym from quote"
        }
    },
   "getter":{
    "interval": "0D00:05"
   },
   "setter":{
    "mode": "request",
    "interval": "0D00:01",
    "cachestokeep": 3,
    "compression": "16 3 0",
    "maxresultmb": 1024,
    "maxdatespan": 7
   }
}
```

Config is read when a process starts, so restart setter after a change:

```bash
./torq.sh stop setter1 && ./torq.sh start setter1
```

## Running setter

Both modes delete all caches and requests every 24 hours.

### Static mode

Set `"mode": "static"` and an `interval`. Every interval setter runs each component cache's `staticmode` query through the gateway and saves a new build. When the build completes, the `<cachename>` symlink moves to it and older builds are deleted.

### Request mode

Set `"mode": "request"`. There is no timer: a user asks for a cache, then setter builds it when triggered.

1. From any TorQ process, write a request with one query per component cache:

```q
Save down an arg file in the <asyncprocessname> folder for the request mode of the Anycache system.
```

2. Trigger the build on setter, then read the result:

```q
h:hopen `:setterhost:setterport:user:password;
(neg h)".anycache.setter.detectandwritecache[]"
```

Request queries must be a select or exec that filters on a date with `=` or `within`, covering at most `maxdatespan` days.
Results over `maxresultmb` are not saved, and only the last `cachestokeep` builds and requests are kept.

## KX Dashboard

Setter exposes the newest completed cache build over IPC:

- `.anycache.setter.getcache[`cache1]` - data of a component cache from the newest completed build
- `.anycache.setter.cachebuilds[]` - one row per cache build on disk: name, start, end and component caches
- `.anycache.setter.latestcache[]` - path of the newest completed build

KX Dashboards connects to setter.

1. In KX Dashboards add a Connection to setter process.
2. Add a Query data source on that connection, set Subscription to Polling every few seconds, and point a Data Grid at it:

       .anycache.setter.getcache[`cache1]

   Same for `cache2`.
3. Add a third data source for the cache builds and show it in a Data Grid:

       .anycache.setter.cachebuilds[]
