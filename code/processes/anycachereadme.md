AnyCache README

## KDB-X Dashboard

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
