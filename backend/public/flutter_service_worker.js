'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "e66cfde18d1e8d9ee4b3fe7b8a286283",
"version.json": "90f0a4de3d79c28df80f8b271963e5d5",
"favicon.ico": "0b9debed17b8c64d19c3e6cc01959291",
"index.html": "7cf889ae45c7066babaa5e102517599f",
"/": "7cf889ae45c7066babaa5e102517599f",
"main.dart.js": "2a7b93ddfa2bc155b994455dc57975f6",
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
"manifest.json": "6b0413966310ac9eb9972a0d6953e396",
"assets/AssetManifest.json": "e47315d9b3b489b76d29e07f02beea58",
"assets/backend/assets/images/logo_al.png": "adf11e51f80e0ca9fc25b9061150887d",
"assets/backend/assets/images/logo_y.png": "3f58cb8aa2450149ab20c9f6d368cc15",
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
"assets/backend/assets/images/stadiums/outside/mlb-17-loandepot.png": "95b106edac86983f60483ee314311326",
"assets/backend/assets/images/stadiums/outside/mlb-10-rate.png": "6d980843fde3402a146721be2648fe95",
"assets/backend/assets/images/stadiums/outside/npb-05-jingu.png": "8ebd9a8177bebc92727c6f1d61f7e28f",
"assets/backend/assets/images/stadiums/outside/npb-06-tokyo.png": "a0ea0a6f70f6064d256de18f85e975bb",
"assets/backend/assets/images/stadiums/outside/npb-10-koshien.png": "456c5c1c57ec08ddc7d702217deaf69b",
"assets/backend/assets/images/stadiums/outside/npb-12-fukuoka.png": "acdf9fa09c93f709f2001595c459680f",
"assets/backend/assets/images/stadiums/outside/mlb-25-pnc.png": "6ca4f59957f14eed15b7beb3041f1044",
"assets/backend/assets/images/stadiums/outside/mlb-24-busch.png": "b6298244226aa4f7ac17e8d41fb32cb6",
"assets/backend/assets/images/stadiums/outside/npb-02-miyagi.png": "f171b7c379fdb99f97db832a7fb05595",
"assets/backend/assets/images/stadiums/outside/npb-03-belluna.png": "f8c46b866631f35211b56d0a9e2c8a8f",
"assets/backend/assets/images/stadiums/outside/mlb-23-american-family.png": "0eb327c5284022f5bc4caf3d019c8613",
"assets/backend/assets/images/stadiums/outside/mlb-29-chase.png": "269ebe886680b5375ee745a0ec8f0e5f",
"assets/backend/assets/images/stadiums/outside/mlb-09-target.png": "f2c50e14d8559fb1a02d0b465e95f722",
"assets/backend/assets/images/stadiums/outside/npb-09-osaka.png": "5e33f5ca3549063b571ffa1e07bdeb33",
"assets/backend/assets/images/stadiums/outside/mlb-12-globe-life.png": "bafcd885f337ae3fe5f8b74dbd0ace1f",
"assets/backend/assets/images/stadiums/outside/mlb-30-coors.png": "25dcf30af003245a9041a9b2615c89b4",
"assets/backend/assets/images/stadiums/outside/mlb-27-petco.png": "1d5b34fe4fef3356d90af48fe82ba8a4",
"assets/backend/assets/images/stadiums/outside/mlb-05-camden.png": "bbadc67668d1af5314d60a2ad3ee2cfb",
"assets/backend/assets/images/stadiums/outside/mlb-18-citi.png": "58354176a8bc448b31f422ee4636f333",
"assets/backend/assets/images/stadiums/outside/mlb-28-oracle.png": "844767b92e22996d453185fb7d883b31",
"assets/backend/assets/images/stadiums/outside/mlb-19-citizens.png": "e71ecfccc068f3222b779d1083655845",
"assets/backend/assets/images/stadiums/outside/mlb-13-angel.png": "e9f9c92a52a82425966c8771e1a11ce0",
"assets/backend/assets/images/stadiums/outside/mlb-20-nationals.png": "e1249e083add00efb51e4f00e8877235",
"assets/backend/assets/images/stadiums/outside/mlb-04-steinbrenner.png": "30deb28edab9784ba9bf968cb736af22",
"assets/backend/assets/images/stadiums/outside/mlb-16-truist.png": "e4b73cf18beed1badd3e9910da6f855c",
"assets/backend/assets/images/stadiums/outside/mlb-21-wrigley.png": "83bec546e7839ad2b1ce83b4478add85",
"assets/backend/assets/images/stadiums/outside/mlb-22-great-american.png": "9cf6b11e1a61e2531074cbdd94e8f10d",
"assets/backend/assets/images/stadiums/outside/mlb-08-kauffman.png": "ce294462089e81f98dd49933550d0960",
"assets/backend/assets/images/stadiums/outside/mlb-26-dodger.png": "a94d5ae3bc647dbcf2ee5399ad6e8e6f",
"assets/backend/assets/images/stadiums/outside/mlb-07-comerica.png": "a86cc488c7fec0e61b5bb0a06bcb5626",
"assets/backend/assets/images/stadiums/outside/mlb-03-rogers.png": "42c7a088d68a83bd908d9016c2bb2eec",
"assets/backend/assets/images/stadiums/outside/mlb-15-sutter.png": "e0ea4122e156e799d33d0312f73bb08b",
"assets/backend/assets/images/stadiums/outside/npb-08-nagoya.png": "d64b837a7c349a114bb77f6317ceaea5",
"assets/backend/assets/images/stadiums/outside/mlb-01-yankee.png": "79d92e09e99046c87d134978f9322f9e",
"assets/backend/assets/images/stadiums/outside/npb-01-escon.png": "1e1f9af837e0f387422e2a91308f07ba",
"assets/backend/assets/images/stadiums/outside/mlb-11-daikin.png": "7cd5e477f14ce2b01ced52932ac24612",
"assets/backend/assets/images/stadiums/outside/npb-11-hiroshima.png": "19c50aaa13281b374c07ed60d0e6b61a",
"assets/backend/assets/images/stadiums/outside/mlb-06-progressive.png": "036350402060f2110c3e856662d51632",
"assets/backend/assets/images/stadiums/outside/mlb-14-tmobile.png": "3a1e4bfac5a5e1656e0c6ff2b93e7204",
"assets/backend/assets/images/stadiums/outside/npb-07-yokohama.png": "424110522b754ca60b5a611cfc5ebdf6",
"assets/backend/assets/images/stadiums/outside/mlb-02-fenway.png": "8fc381d92325d98491ccc7e61c40398b",
"assets/backend/assets/images/stadiums/outside/npb-04-zozo.png": "1e86f74b9bbeac78cbc969da626c93c6",
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
"assets/backend/assets/images/k-central.webp": "a4f9b849b1b70c184807b3094c0b9b2f",
"assets/backend/assets/images/team_db.png": "4ff3b89d799a85f5774f9f93d7ccf6f7",
"assets/backend/assets/images/logo_league_central.webp": "685dea218c865177d315d5315eebae26",
"assets/backend/assets/images/logo_nl.png": "9702b1488dbe557b0b90964078bda1b4",
"assets/NOTICES": "34f97ecb5afa316d13f3a6b9a0f8ed50",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "04efc32ec857b50d7329d38f41bd2a23",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "c16dc51841e744f9b97c6414b3a753a8",
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
