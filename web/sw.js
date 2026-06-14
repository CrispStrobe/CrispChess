// CrispChess Service Worker — cache app shell for offline play.

const CACHE_NAME = 'crispchess-v1';
const APP_SHELL = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/manifest.json',
  '/favicon.png',
  '/flutter.js',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/maia3-bundle.js',
  '/frozenight_bridge.js',
  '/maia3_bridge.js',
  '/maia3_onnx_bridge.js',
  '/lc0_onnx_bridge.js',
  '/sound_bridge.js',
  '/cache_helper.js',
];

// Install — cache app shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[SW] Caching app shell');
      return cache.addAll(APP_SHELL);
    })
  );
  self.skipWaiting();
});

// Activate — clean old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      )
    )
  );
  self.clients.claim();
});

// Fetch — cache-first for app shell, network-first for everything else
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Skip non-GET requests
  if (event.request.method !== 'GET') return;

  // Skip cross-origin requests (CDN engines, ONNX models)
  if (url.origin !== self.location.origin) return;

  // Cache-first for static assets
  if (url.pathname.match(/\.(js|css|wasm|png|svg|json|ico)$/) ||
      url.pathname === '/' || url.pathname === '/index.html') {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request).then((response) => {
          // Cache successful responses
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        });
      })
    );
    return;
  }

  // Network-first for everything else
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
