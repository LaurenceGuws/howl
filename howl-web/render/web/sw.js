const CACHE = 'howl-web-canary-v1';
const SHELL = [
  '/', '/host.mjs', '/style.css', '/runtime.mjs', '/wire.wasm',
  '/render.wasm', '/font.bin', '/manifest.webmanifest', '/icon.png',
];
const SHELL_SET = new Set(SHELL);

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)));
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) if (name !== CACHE) await caches.delete(name);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || !SHELL_SET.has(url.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(event.request);
      // An Access redirect or login response is authentication UI, never app cache.
      if (response.ok && !response.redirected && new URL(response.url).origin === self.location.origin) {
        await cache.put(event.request, response.clone());
      }
      return response;
    } catch (error) {
      const cached = await cache.match(event.request);
      if (cached) return cached;
      throw error;
    }
  })());
});
