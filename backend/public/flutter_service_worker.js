'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "4bbb902069c43ce89758cf2b5ecd7ce7",
"version.json": "90f0a4de3d79c28df80f8b271963e5d5",
"favicon.ico": "0b9debed17b8c64d19c3e6cc01959291",
"index.html": "7cf889ae45c7066babaa5e102517599f",
"/": "7cf889ae45c7066babaa5e102517599f",
"main.dart.js": "adedd7b5606054bbd13ce49ebc5d46e7",
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
"assets/AssetManifest.json": "3370e74f69afb79a44af184e81dbcd2e",
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
"assets/AssetManifest.bin.json": "452427646e6f0c38cc064ba4ada77ab7",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "c4a5e5ebf9283afff73830d61fc74938",
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
