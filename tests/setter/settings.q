// Settings, mock data and helper functions for the setter tests
// setter runs as its own proc (testsetter1) - the tests drive it over IPC and check its log files

// IPC connection parameters
.servers.CONNECTIONS:`rdb`segmentedtickerplant`setter;
.servers.USERPASS:`admin:admin;

// Paths to process CSV and the directory test caches are built in
testpath:getenv[`KDBTESTS],"/setter/";
processcsv:testpath,"process.csv";
.tst.root:testpath,"tmpcache";
.tst.main:` sv (hsym `$.tst.root),`myfirstcache;

// Function projections (using functions from helperfunctions.q)
startproc:startorstopproc["start";;processcsv];
stopproc:startorstopproc["stop";;processcsv];

// Mock data published to the stp - the stp adds the time column
.tst.trade:(`AAPL`MSFT`IBM;101 202 303f;10 20 30i;000b;"   ";"NNN";`buy`sell`buy);
.tst.quote:(`AAPL`MSFT`IBM;100 200 300f;102 202 302f;1 2 3;4 5 6;"RRR";"NNN";`src1`src1`src1);

// Cache timer setter registers in static mode, and the interval used for the timer tests
.tst.setterfunc:(`.anycache.setter.detectandwritecache;`);
.tst.interval:0D00:00:05;

// Query cache2 runs in static mode is swapped for one the rdb can't run to make a build fail
.tst.badquery:"select from nosuchtable";

// Setter's log files - info lines go to out, error lines go to err
.tst.logfiles:hsym `$getenv[`KDBLOG],/:("/out_";"/err_"),\:"testsetter1.log";

// Mark the current end of setter's logs
.tst.mark:{.tst.logstart:count each read0 each .tst.logfiles};

// Log lines setter has written since the mark
.tst.newlogs:{raze .tst.logstart _' read0 each .tst.logfiles};

// Check if setter has logged a matching anycache line since the mark - KDB-X like only allows * at the start or end of a pattern
.tst.logged:{any .tst.newlogs[] like "*|anycache|",x};

// Check setter has logged matching anycache info lines in the given order since the mark
.tst.inorder:{l:.tst.logstart[0]_read0 first .tst.logfiles; (til count x)~iasc {[l;p] first where l like "*|anycache|",p}[l] each x};

// Clear down test caches, set setter's mode (1b request / 0b static) and mark setter's logs
.tst.reset:{[isrequest]
  system "rm -rf ",.tst.root;
  setterh({.anycache.setter.isrequest:x};isrequest);
  .tst.mark[];
 };

// Wait up to <timeout> for <cond> to be true - setter's timer runs on its own, so poll rather than sleep a fixed time
.tst.waitfor:{[cond;timeout] st:.z.p; while[(not cond[]) and .z.p<st+timeout; system "sleep 0.8"]; cond[]};

// Trigger a cache build on setter - in request mode this is what the user does after making a request
.tst.build:{setterh".anycache.setter.detectandwritecache[]"};

// Main cache builds (oldest first), the latest build and when a build started
.tst.builds:{` sv' .tst.main,'b where (b:key .tst.main) like "myfirstcache_*"};
.tst.latest:{last .tst.builds[]};
.tst.started:{get ` sv x,`start};

// Names of cache request directories
.tst.requests:{b where (b:key .tst.main) like "asynccache_*"};

// Create a completed static cache built <age> ago, with the cachename link pointing at it - data is ([]old:enlist 1b)
.tst.mkcache:{[age]
  d:` sv .tst.main,n:`$"myfirstcache_",string ts:.z.P-age;
  {(` sv x,y,`data) set ([]old:enlist 1b); (` sv x,y,`end) set .z.P}[d] each `cache1`cache2;
  (` sv d,`start) set ts;
  (` sv d,`end) set ts;
  system "ln -sfn ",(string n)," ",1_string ` sv .tst.main,`myfirstcache;
  d
 };

// Point the getter (what readers use) at the test caches, and read a component cache the way a reader does
.anycache.getter.cacheconfig[`cacherootdir]:.tst.root;
.tst.read:{.anycache.getter.loadcaches[]; get ` sv `.anycache.cache,x};

// Request args for the given sym - requests are made with .anycache.getter.requestnewcache
.tst.args:{[s] `cache1`cache2!{enlist[`query]!enlist x} each ("select from trade where sym=`",s;"select from quote where sym=`",s)};
