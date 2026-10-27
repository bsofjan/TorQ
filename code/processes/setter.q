// Setter process to set cache to disk

\d .anycache

// Save cache down to disk
setter.savecachedowntodisk:{[data;filepath] (hsym filepath) set data };

// Get location of cache config and load it in.
setter.cacheconfiglocation:.proc.getconfigfile["cacheconfig.json"];
setter.cacheconfig:.j.k raze read0 hsym first setter.cacheconfiglocation;

// Mode of cache
setter.isrequest: "request" ~ setter.cacheconfig.setter.mode;

// Number of main cache builds (and cache requests) to keep on disk in request mode
setter.cachestokeep:$[`cachestokeep in key setter.cacheconfig`setter; "j"$setter.cacheconfig.setter.cachestokeep; 3];

// Max size in MB of the data a component cache query can return
setter.maxresultmb:$[`maxresultmb in key setter.cacheconfig`setter; setter.cacheconfig.setter.maxresultmb; 1024];

// Max number of days a request query can cover, counting both ends of its date range
setter.maxdatespan:$[`maxdatespan in key setter.cacheconfig`setter; "j"$setter.cacheconfig.setter.maxdatespan; 7];

setter.init:{
    // Register timers
    if[not setter.isrequest; setter.registertimers[]];
    setter.registerflushtimer[];
    setter.registerconnections[];
 };

setter.detectandwritecache:{ 
    cacheinfo:setter.detectcachetobuild[];
    if[not count cacheinfo;
        :(::)
    ];
    setter.writetoken[;`start] each cachepath:cacheinfo`cachepath;
    //Included some basic error trapping here
    success:{.[setter.generateandwritecache; (x;y); {[cachepath;err] .lg.e[`anycache; "cache build failed for component cache ",(string last ` vs cachepath),": ",err];0b}[x]]}'[cachepath; cacheinfo`args];
    if[not all success;
        .lg.e[`anycache; "main cache build failed, not completing ",1_string first ` vs first cachepath];
        setter.cleanupcache each cachepath;
        :(::)
    ];
    setter.writetoken[;`end] each cachepath;
    //Can eject now if there are still caches to be built in the main cache
    if[not count remainingcaches:cacheinfo`maincachepath;
        :(::)
    ];
    setter.completecache cacheinfo`maincachepath
 };

setter.writetoken:{[dir;stage] 
    //accepts start or end and saves the current time as a timestamp to a flat file 
    //in dir as `:startTime or `:endTime
    (` sv (dir;stage)) set .z.P
 };

setter.detectcachetobuild:{
    cachename: setter.cacheconfig`cachename;
    asyncprocessname: setter.cacheconfig`asyncprocessname;
    maincachepath:` sv (hsym `$setter.cacheconfig.cacherootdir),`$cachename;
    caches:` sv' maincachepath,'(key maincachepath) where (key maincachepath) like cachename,"_*";
    if[not 0 = count caches; cachewithmaxstarttime:starts ? max starts:cands!{get ` sv x,`start} each cands:key[d1:caches!key each caches]];

    latestcache:{[caches;cachename;cachewithmaxstarttime]
    if[(0 = count caches) or (setter.isrequest); :`cachename`newcache!(cachename,"_",string .z.P;1b)];
    if[(not setter.isrequest) and (("N"$setter.cacheconfig.setter.interval) - 0D00:00:03) < .z.P - "P"$@[last "_" vs string cachewithmaxstarttime;13 16 19;:;"::."];:`cachename`newcache!(cachename,"_",string .z.P;1b)];
    :`cachename`newcache!(cachewithmaxstarttime;0b)}[caches;cachename;cachewithmaxstarttime];

    if[latestcache[`newcache]; setter.writetoken[` sv maincachepath,`$latestcache[`cachename];`start]];
    if[latestcache[`newcache]; cachewithmaxstarttime:` sv maincachepath,`$latestcache[`cachename]];
    .lg.o[`anycache; $[latestcache`newcache; "starting new main cache build "; "resuming main cache build "],1_string cachewithmaxstarttime];

    componentcaches:` sv' cachewithmaxstarttime,/:key setter.cacheconfig.componentcaches;
    incompletecomponentcaches:key[d2] where not `end in/: value d2:componentcaches!key each componentcaches;
    .lg.o[`anycache; "component caches to build: ",$[count incompletecomponentcaches; ", " sv string last each ` vs' incompletecomponentcaches; "none"]];
    setter.writetoken[;.proc.procname] each incompletecomponentcaches;
    args:(count incompletecomponentcaches)#enlist`;
    if[setter.isrequest;
        argpaths:` sv' maincachepath,'(key maincachepath) where (key maincachepath) like asyncprocessname,"*";
        maxstarttime:string first max "P"$-1#' "_" vs' string argpaths;
        argwithmaxstarttime:first argpaths where argpaths like "*",maxstarttime;
        args: get ` sv argwithmaxstarttime,`args
        ];
    `maincachepath`cachepath`args!(maincachepath;incompletecomponentcaches;args)
 };

setter.generateandwritecache:{[cachepath; args] 
    cachename:last ` vs cachepath;
    connectiondetails: $[setter.isrequest; `hdb`rdb; `$trim each "," vs (setter.cacheconfig.componentcaches[cachename])`datasource];
    if[`rdb`hdb ~ connectiondetails; connectiondetails: `hdb`rdb];
    $[setter.isrequest; querydetails: args`query; querydetails: (setter.cacheconfig.componentcaches[cachename])`staticmode ];
    // Request queries must have a date or date span
    if[setter.isrequest; if[not setter.checkdates[cachename;querydetails]; :0b]];
    gateway:.servers.gethandlebytype[`gateway;`any];
    .lg.o[`anycache; "requesting data for component cache ",(string cachename)," from ",(", " sv string connectiondetails)];
    cache: setter.querygateway[gateway;querydetails;connectiondetails];
    //The gateway sends errors back as strings
    if[10h=type cache;
        .lg.e[`anycache; "query for component cache ",(string cachename)," failed on the gateway: ",cache];:0b];
    //Return an error if the cache is over the size limit
    if[setter.maxresultmb < sizemb:(-22!cache)%1024*1024;
        .lg.e[`anycache; "result for component cache ",(string cachename)," is ",(string sizemb)," MB, over the maxresultmb of ",(string setter.maxresultmb),", not saving"];:0b];
    // Mock data
    // cache:`a`b`c!(1 2 3; (`d`e!4 5); 6);
    .lg.o[`anycache; "saving data for component cache ",(string cachename)," to ",1_string datapath:` sv cachepath,`data];
    .anymap.writetoanymap[datapath;cache];
    .lg.o[`anycache; "data save completed for component cache ",string cachename];
    :1b
 };

setter.querygateway:{[gateway;query;servertypes]
    neg[gateway](`.gw.asyncexecjpt;query;servertypes;{raze {$[`date in cols x; delete date from x; x]} each x};();0Wn);
    neg[gateway][];
    gateway[]
 };

setter.checkdates:{[cachename;query]
    //Request queries must be a select or exec, filtering on a single date or a date range of at most maxdatespan days
    parsed:parse query;
    if[not (?) ~ first parsed;
        .lg.e[`anycache; "query for component cache ",(string cachename)," is not a select or exec, not building"];
        :0b
        ];
    constraints:raze parsed 2;
    constraints:constraints where (first each constraints) in (=;within);
    dates:raze d where (type each d:last each constraints) in -14 14h;
    if[not count dates;
        .lg.e[`anycache; "query for component cache ",(string cachename)," has no date, not building"];
        :0b
        ];
    if[setter.maxdatespan < span:1+(max dates)-min dates;
        .lg.e[`anycache; "query for component cache ",(string cachename)," spans ",(string span)," days, over the maxdatespan of ",(string setter.maxdatespan),", not building"];
        :0b
        ];
    :1b
 };

setter.cleanupcache:{[cachepath]
    //Want to just remove the component cache (cachename) from the main cache directory in event of a failure
    //Directory contains token files so use deldir rather than hdel, which only removes empty directories
    .lg.o[`anycache; "removing failed component cache ",1_string cachepath];
    .os.deldir cachepath
 };

setter.deleteoldcache:{[cachepath]
    .lg.o[`anycache; "deleting old cache ",1_string cachepath];
    .os.deldir cachepath
 };

setter.removeoldrequestcaches:{[maincachepath]
    //In request mode keep the most recent cachestokeep main cache builds and cache requests, delete the rest
    //Directory names end in their start timestamp so sorting by name sorts by age
    names:key maincachepath;
    old:raze {neg[setter.cachestokeep] _ asc x where x like y}[names;] each ((string last ` vs maincachepath),"_*";setter.cacheconfig[`asyncprocessname],"_*");
    setter.deleteoldcache each ` sv' maincachepath,'old;
 };

setter.completecache:{[maincachepath]
    cachename: string last ` vs maincachepath;
    caches:` sv' maincachepath,'(key maincachepath) where (key maincachepath) like cachename,"_*";
    latestcache:string last ` vs starts ? max starts:cands!{get ` sv x,`start} each cands:key[d1:caches!key each caches];
    latestcachefilepath: ` sv maincachepath,`$latestcache;
    setter.writetoken[latestcachefilepath;`end];
    .lg.o[`anycache; "main cache build completed ",1_string latestcachefilepath];
    if[setter.isrequest; setter.removeoldrequestcaches maincachepath];
    if[(not setter.isrequest) and not .os.NT; system"ln -sfn ", latestcache, " ", (1_string maincachepath), "/", cachename];
    if[(not setter.isrequest) and .os.NT;
        target: .os.pth 1_string latestcachefilepath;
        link: .os.pth (1_string maincachepath), "/", cachename;
        system"cmd /c if exist \"", link, "\" rmdir \"", link, "\"";
        system"cmd /c mklink /J \"", link, "\" \"", target, "\"";
    ];
    if[not setter.isrequest; setter.deleteoldcache each ` sv' maincachepath,'{x where not x like "asynccache*"} (key maincachepath) except (`$cachename;`$latestcache)]
 };

setter.flushcaches:{
    //Delete caches every 24 hours
    maincachepath:` sv (hsym `$setter.cacheconfig.cacherootdir),`$setter.cacheconfig`cachename;
    setter.deleteoldcache each ` sv' maincachepath,'key maincachepath
 };

// Read API for KX Dashboards - reads the newest completed build from disk

setter.readtoken:{[dir;stage] $[stage in key dir; get ` sv (dir;stage); 0Np]};

setter.cachebuilds:{
    // Get cache builds, return newest first
    maincachepath:` sv (hsym `$setter.cacheconfig.cacherootdir),`$setter.cacheconfig`cachename;
    builds:(key maincachepath) where (key maincachepath) like setter.cacheconfig[`cachename],"_*";
    paths:` sv' maincachepath,'builds;
    `start xdesc ([] build:builds; start:setter.readtoken[;`start] each paths; end:setter.readtoken[;`end] each paths; componentcaches:{", " sv string key[x] except `start`end} each paths)
 };

setter.latestcache:{
    //Path of the newest completed main cache build - null if there isn't one yet
    completed:exec build from setter.cachebuilds[] where not null end;
    maincachepath:` sv (hsym `$setter.cacheconfig.cacherootdir),`$setter.cacheconfig`cachename;
    $[count completed; ` sv maincachepath,first completed; `]
 };

setter.getcache:{[cachename]
    // Data of a component cache from the newest completed build
    if[null latest:setter.latestcache[]; '"no completed cache build on disk"];
    data:get ` sv latest,cachename,`data;
    $[.Q.qt data; 0!data; data]
 };

.api.add[`.anycache.setter.getcache;1b;"Data of a component cache from the newest completed build";"[symbol: component cache name, e.g. `cache1]";"table (or whatever the component cache query returned)"];
.api.add[`.anycache.setter.cachebuilds;1b;"Main cache builds on disk, newest first, with their start and end times and component caches";"[]";"table"];
.api.add[`.anycache.setter.latestcache;1b;"Path of the newest completed main cache build";"[]";"symbol - null if no build has completed"];

setter.registertimers:{
    .timer.repeat[0D00:00:01 + .proc.cp[];0D01:00:01 + .proc.cp[];"N"$setter.cacheconfig.setter.interval;(`.anycache.setter.detectandwritecache; `);"Running static cachebuilder on a timer"];
 };

setter.registerflushtimer:{
    .timer.repeat[1D + .proc.cp[];0Wp;1D;(`.anycache.setter.flushcaches; `);"Delete caches every 24 hours"];
 };

setter.registerconnections:{
    .servers.startupdepcycles[`gateway;3;1];
 };

setter.init[];

\d .