'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "f23b6ecd7afb7124ae5cded5970dc5d3",
"version.json": "90f0a4de3d79c28df80f8b271963e5d5",
"favicon.ico": "0b9debed17b8c64d19c3e6cc01959291",
"index.html": "e438d00f4f42772511fa509227eea38c",
"/": "e438d00f4f42772511fa509227eea38c",
"main.dart.js": "0e401fd0e196a1d1fda5362165970454",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"favicon.png": "48c2581436fbca85f692d8e41b7b851d",
"icons/favicon-48.png": "cb488c05fb3a6bb83ef7065a4a388721",
"icons/favicon-64.png": "991bba8f3bb1d268a4030a70dad2d9fc",
"icons/favicon-16.png": "415f8bf205948f4a5b47ea7de7915d88",
"icons/Icon-192.png": "6b0d38f870d5df34b290abb12193b79b",
"icons/Icon-maskable-192.png": "6b0d38f870d5df34b290abb12193b79b",
"icons/favicon.png": "48c2581436fbca85f692d8e41b7b851d",
"icons/favicon-32.png": "48c2581436fbca85f692d8e41b7b851d",
"icons/Icon-maskable-512.png": "9a146cb90568db56932abc52620fb846",
"icons/favicon.svg": "11ade35e0a6af5a1816d131c7a96176c",
"icons/Icon-512.png": "9a146cb90568db56932abc52620fb846",
"manifest.json": "8588673b3828cffe60800859da3e323d",
"sitemap.xml": "fda6d8a5a21b7b788de241901e0354fe",
"robots.txt": "fa83f05580d9b4d39585ed9c08a9465f",
"assets/AssetManifest.json": "29554fec6250dea9dd412a98b7b20052",
"assets/backend/assets/images/result_draw.png": "f8b2e9d1c47565a95158ef7c0d0cda13",
"assets/backend/assets/images/logo_al.png": "adf11e51f80e0ca9fc25b9061150887d",
"assets/backend/assets/images/logo_y.png": "3f58cb8aa2450149ab20c9f6d368cc15",
"assets/backend/assets/images/result_lose.png": "30a94e52d15ad0198daef9f594db9349",
"assets/backend/assets/images/logo_japan_series.png": "d060751ab8f9a2764068a7954225fd27",
"assets/backend/assets/images/team_m.png": "3bbb41d5b2a768a761edd2f3f84dcaf1",
"assets/backend/assets/images/team_l.png": "9dbcfd038a9117e47f6216d4329e22c8",
"assets/backend/assets/images/logo_league_pacific.png": "e468b0f19a81f5b4eea51c99bbe45971",
"assets/backend/assets/images/logo_mlb.png": "1d14695e6741ec2b02e9c19100e05f9c",
"assets/backend/assets/images/logo_yakyuu_japan.png": "524ac8ef17aeaa6ff8cf871ac65ee6ea",
"assets/backend/assets/images/team_h.png": "b6decba1306bb86bda119c79808e5622",
"assets/backend/assets/images/logo_mlb.webp": "1d89bfe61c15186b820138a3bf9c7704",
"assets/backend/assets/images/k-pacific.webp": "d8b3f998b5fd86d8d3290149d82c43ed",
"assets/backend/assets/images/team_s.png": "d0cd97b0517c29dc3784aedb4ec7f836",
"assets/backend/assets/images/team_d.png": "e927c108ab60eb578bb833766309adc8",
"assets/backend/assets/images/team_e.png": "990396158b50533dde2e933072073e92",
"assets/backend/assets/images/team_g.png": "68fbbee1f9467997a73bf36a7f39318a",
"assets/backend/assets/images/logo_cs_central.png": "76b139e5ba1f54449f62c6d6c0cbfd19",
"assets/backend/assets/images/logo_cs_pacific.png": "594f72b287383e2e3827dc7203d707fe",
"assets/backend/assets/images/logo_npb.png": "b04bcae63dffad44e632a79d6c9a391b",
"assets/backend/assets/images/stadiums/outside/mlb-17-loandepot.png": "859f14fd9108e10f1af1cf28039d1113",
"assets/backend/assets/images/stadiums/outside/mlb-10-rate.png": "23b313567fa1d981dffdd6226fa645f3",
"assets/backend/assets/images/stadiums/outside/npb-05-jingu.png": "3d2296e7b2d72af2f2e795d58f5c536b",
"assets/backend/assets/images/stadiums/outside/npb-06-tokyo.png": "2f46a7b623b93de978dbace035dea794",
"assets/backend/assets/images/stadiums/outside/npb-10-koshien.png": "f87ff1deb23918169e65dfaa49b8656a",
"assets/backend/assets/images/stadiums/outside/npb-12-fukuoka.png": "7bb1dadc42b7a09cb1245c9d46f1207a",
"assets/backend/assets/images/stadiums/outside/mlb-25-pnc.png": "397fdf8c736c057f3d15660f77e33a85",
"assets/backend/assets/images/stadiums/outside/mlb-24-busch.png": "c908058d01e025a7d5a5df1f70cb261a",
"assets/backend/assets/images/stadiums/outside/npb-02-miyagi.png": "3e8a181cdb6cc75f838187e224f85447",
"assets/backend/assets/images/stadiums/outside/npb-03-belluna.png": "a02c414ceea9a89177e178b12b9a2f80",
"assets/backend/assets/images/stadiums/outside/mlb-23-american-family.png": "622fbb6ba32aa167d405ab5394b00c17",
"assets/backend/assets/images/stadiums/outside/mlb-29-chase.png": "2b6159f4aeff5c92745f2593cd25f1c7",
"assets/backend/assets/images/stadiums/outside/mlb-09-target.png": "c7395755f734a3a941129e73e0f2dc93",
"assets/backend/assets/images/stadiums/outside/npb-09-osaka.png": "e8d5aa9e456ff394699b250d6d39113d",
"assets/backend/assets/images/stadiums/outside/mlb-12-globe-life.png": "0a577ff74e59144dd63391a92ab903f0",
"assets/backend/assets/images/stadiums/outside/mlb-30-coors.png": "c6db6431938a31e8c2c6e64df2ce771e",
"assets/backend/assets/images/stadiums/outside/mlb-27-petco.png": "1417491f321fc0f08480dbcc97bdb684",
"assets/backend/assets/images/stadiums/outside/mlb-05-camden.png": "8a986d74ae9d7469e9822b9b8300fed6",
"assets/backend/assets/images/stadiums/outside/mlb-18-citi.png": "31a7dff340388db944bfe7f8465ef4e6",
"assets/backend/assets/images/stadiums/outside/mlb-28-oracle.png": "094f05e9ba54dbd89644479053bf9289",
"assets/backend/assets/images/stadiums/outside/mlb-19-citizens.png": "59792c1899ccb684922aacab8ee38977",
"assets/backend/assets/images/stadiums/outside/mlb-13-angel.png": "1430bba3e9b3a2a9f9372023cdbe1c0b",
"assets/backend/assets/images/stadiums/outside/mlb-20-nationals.png": "3162c20504637aad12530a21ddcee218",
"assets/backend/assets/images/stadiums/outside/mlb-04-steinbrenner.png": "8c110300b027f47fab8816ba7c2b0e9e",
"assets/backend/assets/images/stadiums/outside/mlb-16-truist.png": "c0071148cc623a1c9b9776eb7f07c767",
"assets/backend/assets/images/stadiums/outside/mlb-21-wrigley.png": "0b8bd6c3d54400920cf452c0c114b0e8",
"assets/backend/assets/images/stadiums/outside/mlb-22-great-american.png": "80bbecb00e85b4a9c9f78e438367a149",
"assets/backend/assets/images/stadiums/outside/mlb-08-kauffman.png": "24d03dd3ac3cad87d38fb8f7935a51f5",
"assets/backend/assets/images/stadiums/outside/mlb-26-dodger.png": "ac0d86b4d1b36e30842377a4677176e3",
"assets/backend/assets/images/stadiums/outside/mlb-07-comerica.png": "59d2d928865e4e52bd79e685431e1008",
"assets/backend/assets/images/stadiums/outside/mlb-03-rogers.png": "3a9ff9e4a9bed9fefe9dd9bce130a622",
"assets/backend/assets/images/stadiums/outside/mlb-15-sutter.png": "d0a2a4f34f518ff58d5b11ba8d9a6964",
"assets/backend/assets/images/stadiums/outside/npb-08-nagoya.png": "eacfbebd20d6160204bfa60355e3a431",
"assets/backend/assets/images/stadiums/outside/mlb-01-yankee.png": "ef105d201d29db5e8d66f864ebb139b8",
"assets/backend/assets/images/stadiums/outside/npb-01-escon.png": "c562027e1a2eefe4325008a3c6beaf36",
"assets/backend/assets/images/stadiums/outside/mlb-11-daikin.png": "61be2d79d515b9f904a94a7981f29c46",
"assets/backend/assets/images/stadiums/outside/npb-11-hiroshima.png": "905637a3787973aec8357b0d51405625",
"assets/backend/assets/images/stadiums/outside/mlb-06-progressive.png": "db4371782f1a8c10fb231070ad6ab0f5",
"assets/backend/assets/images/stadiums/outside/mlb-14-tmobile.png": "e5c77f48c4da1d4e4e7c433b1718c1f4",
"assets/backend/assets/images/stadiums/outside/npb-07-yokohama.png": "8f606877f7a23078888b1814e593c326",
"assets/backend/assets/images/stadiums/outside/mlb-02-fenway.png": "53dc3f36656824edb962a21eff6d7a75",
"assets/backend/assets/images/stadiums/outside/npb-04-zozo.png": "aac1fb587f838d6b6c196208780eee58",
"assets/backend/assets/images/stadiums/inside/mlb-22-busch.jpg": "eccb958d0ca56ee6c9485ed6697eb3d5",
"assets/backend/assets/images/stadiums/inside/npb-05-jingu.jpg": "832d0b3611eded3344cd12ef2576d457",
"assets/backend/assets/images/stadiums/inside/npb-10-koshien.jpg": "860ea99a5aca4111ab538e443c20b4f1",
"assets/backend/assets/images/stadiums/inside/mlb-13-tmobile.jpg": "3f02fc7efdb5647c0c9e4658b6fbc29f",
"assets/backend/assets/images/stadiums/inside/mlb-01-fenway.jpg": "54a7a8492db879b60ca555f2bd2bdea7",
"assets/backend/assets/images/stadiums/inside/npb-12-fukuoka.jpg": "97b10607bc313871ed8ff11ab94f7a76",
"assets/backend/assets/images/stadiums/inside/mlb-02-wrigley.jpg": "4c113e6391767e5a815e6b13a2e8eb1d",
"assets/backend/assets/images/stadiums/inside/mlb-28-truist.jpg": "2267fa0245006f37dec768627635496d",
"assets/backend/assets/images/stadiums/inside/mlb-20-petco.jpg": "359008e390f117ad7b672c1d0385819f",
"assets/backend/assets/images/stadiums/inside/npb-02-miyagi.jpg": "596421c076dc895058399c76b6a85b63",
"assets/backend/assets/images/stadiums/inside/mlb-07-rate.jpg": "ed22f3e6c98e64c4171805abef838f17",
"assets/backend/assets/images/stadiums/inside/mlb-21-citizens.jpg": "84d30ec4806ad746e92b2602c194966a",
"assets/backend/assets/images/stadiums/inside/npb-03-belluna.jpg": "e8cede50a218acf1914df89d25e30db5",
"assets/backend/assets/images/stadiums/inside/mlb-03-dodger.jpg": "6b884c4c22be37462610cd61af6c7b30",
"assets/backend/assets/images/stadiums/inside/mlb-30-sutter-health.jpg": "1cf9e25bbaaa2b2f9cdf0617649a0ca4",
"assets/backend/assets/images/stadiums/inside/npb-09-osaka.jpg": "e82b9471a6350783edfaaa84a96f42cd",
"assets/backend/assets/images/stadiums/inside/mlb-27-loandepot.jpg": "928025630641814437a3edf3d784d184",
"assets/backend/assets/images/stadiums/inside/mlb-04-angel.jpg": "7ad43d4e66cebac4241a5ce90cb458ca",
"assets/backend/assets/images/stadiums/inside/mlb-11-tropicana.jpg": "601de611ad8e5d48f8007ea0ba8bf5c6",
"assets/backend/assets/images/stadiums/inside/mlb-18-pnc.jpg": "ca0f94d2574d70c7da2a45fc96a5a979",
"assets/backend/assets/images/stadiums/inside/mlb-08-camden.jpg": "956c44a4eb8c48968e6fdc7224bbad03",
"assets/backend/assets/images/stadiums/inside/mlb-10-coors.jpg": "252afb1b13ba497ca5fd476249a6aca6",
"assets/backend/assets/images/stadiums/inside/mlb-25-yankee.jpg": "d0e2f581349b92dc39e42e94a863b375",
"assets/backend/assets/images/stadiums/inside/npb-06-chiba.jpg": "f60289a15eb109dbdffbc03da446c74e",
"assets/backend/assets/images/stadiums/inside/npb-04-tokyo.jpg": "2a8c3083fbe204a4a75bff5274561e7a",
"assets/backend/assets/images/stadiums/inside/mlb-23-nationals.jpg": "7005c79e64bee49f136ba1bbc6a219df",
"assets/backend/assets/images/stadiums/inside/mlb-26-target.jpg": "5ff53467692f5584b50ecab4ddea0d62",
"assets/backend/assets/images/stadiums/inside/mlb-15-comerica.jpg": "83c64dff6e494a88cb9d4aeaf946146c",
"assets/backend/assets/images/stadiums/inside/mlb-05-kauffman.jpg": "fe43837f298574578564b8f0d0d4aeb1",
"assets/backend/assets/images/stadiums/inside/mlb-19-great-american.jpg": "e88b9a195ba57730081a3d34c96172a9",
"assets/backend/assets/images/stadiums/inside/mlb-14-daikin.jpg": "c334cd57528ce05d98edcbb0c4b7a3c2",
"assets/backend/assets/images/stadiums/inside/mlb-29-globe-life.jpg": "5739864f6a36c5f074c4d890ef4f3d90",
"assets/backend/assets/images/stadiums/inside/mlb-24-citi.jpg": "24c38ee43f012fd8c6dece4f18f2bdb4",
"assets/backend/assets/images/stadiums/inside/npb-08-nagoya.jpg": "a18bafddf32f91f63bd4d5c973c8f05a",
"assets/backend/assets/images/stadiums/inside/npb-11-hiroshima.jpg": "28eb309dd0b9cf0b32916509964cbf93",
"assets/backend/assets/images/stadiums/inside/npb-01-escon.jpg": "6aa7d1c2bc9e4bc15157ad0e5f8cba18",
"assets/backend/assets/images/stadiums/inside/mlb-06-rogers.jpg": "d20d7293c79badd2d733c1177aabd7f6",
"assets/backend/assets/images/stadiums/inside/mlb-12-chase.jpg": "466000860fe2296dfd6a11a4c638cd82",
"assets/backend/assets/images/stadiums/inside/npb-07-yokohama.jpg": "caf3d4103ed25800748cedeb35b60e73",
"assets/backend/assets/images/stadiums/inside/mlb-16-oracle.jpg": "20b989913f07cf7a3fc0459c5141b848",
"assets/backend/assets/images/stadiums/inside/mlb-09-progressive.jpg": "b704cb9a324f3b96e0250cd79bbd65dc",
"assets/backend/assets/images/stadiums/inside/mlb-17-american-family.jpg": "63cd6d8876fbd40a66f31f0002bf9dc3",
"assets/backend/assets/images/team_f.png": "6ae07b148178f80ce330fdd8328196c5",
"assets/backend/assets/images/team_bs.png": "3b6fef4a3fe362fd4a89b57a85d7bdd6",
"assets/backend/assets/images/team_t.png": "f9a3b5a42595ddf91cefe9158af913f6",
"assets/backend/assets/images/team_c.png": "5df4d3068f61b81816256c66d4583aa8",
"assets/backend/assets/images/result_win.png": "90dd857268442f59631f1d8c722533eb",
"assets/backend/assets/images/k-central.webp": "a4f9b849b1b70c184807b3094c0b9b2f",
"assets/backend/assets/images/team_db.png": "4ff3b89d799a85f5774f9f93d7ccf6f7",
"assets/backend/assets/images/logo_league_central.webp": "685dea218c865177d315d5315eebae26",
"assets/backend/assets/images/logo_nl.png": "9702b1488dbe557b0b90964078bda1b4",
"assets/NOTICES": "34f97ecb5afa316d13f3a6b9a0f8ed50",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "143ef540013f0161d0ce5b32353e23f4",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "4150147ede310a927f2c35cfe5a7f3ef",
"assets/fonts/MaterialIcons-Regular.otf": "f9bc4e756e94d06c9f5ea44b2ec4f464",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
