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
setter.cachestokeep:"j"$setter.cacheconfig.setter.cachestokeep;

setter.init:{
    // Register timers
    if[not setter.isrequest; setter.registertimers[]];
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
    connectiondetails: `$ (setter.cacheconfig.componentcaches[cachename])`datasource;
    $[setter.isrequest; querydetails: args`query; querydetails: (setter.cacheconfig.componentcaches[cachename])`staticmode ];
    .servers.startupdepcycles[connectiondetails;3;1];
    connection:.servers.gethandlebytype[connectiondetails;`any];
    .lg.o[`anycache; "requesting data for component cache ",(string cachename)," from ",(string connectiondetails),": ",-3!querydetails];
    cache: connection querydetails;
    // Mock data
    // cache:`a`b`c!(1 2 3; (`d`e!4 5); 6);
    .lg.o[`anycache; "saving data for component cache ",(string cachename)," to ",1_string datapath:` sv cachepath,`data];
    .anymap.writetoanymap[datapath;cache];
    .lg.o[`anycache; "data save completed for component cache ",string cachename];
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

setter.registertimers:{
    .timer.repeat[0D00:00:01 + .proc.cp[];0D01:00:01 + .proc.cp[];"N"$setter.cacheconfig.setter.interval;(`.anycache.setter.detectandwritecache; `);"Running static cachebuilder on a timer"];
 };

setter.registerconnections:{
    .servers.startupdepcycles[`gateway;3;1];
    gatewayconnection: .servers.gethandlebytype[`gateway;`any];
 };

setter.init[];

\d .