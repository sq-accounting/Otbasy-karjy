/* Отбасы қаржысы - service worker
   Strategy: network-first for the app shell so updates always show when online,
   with a cached fallback so the app still opens offline.
   IMPORTANT: only same-origin GET requests are handled. Supabase API calls,
   Google Fonts, and any POST/PATCH/DELETE go straight to the network and are
   never cached or intercepted. */

const CACHE = "qarjy-cache-v7";
const SHELL = ["./", "./index.html", "./bg.webp", "./bg.jpg", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];

// Pre-cache the app shell on install.
// Add each asset individually so one missing file never aborts the whole precache.
self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      Promise.allSettled(SHELL.map((u) => c.add(u)))
    )
  );
});

// Remove old caches and take control immediately on activate
self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (e) => {
  const req = e.request;

  // Never handle non-GET (writes must reach Supabase untouched)
  if (req.method !== "GET") return;

  // Only handle our own origin; let Supabase / fonts go to the network directly
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Network-first, fall back to cache (so updates show online, app opens offline)
  e.respondWith((async () => {
    try {
      const fresh = await fetch(req);
      // Only cache successful, complete, same-origin responses (skip 404/206/redirects/opaque)
      if (fresh && fresh.ok && fresh.status === 200 && fresh.type === "basic") {
        const cache = await caches.open(CACHE);
        cache.put(req, fresh.clone()).catch(() => {});
      }
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      if (req.mode === "navigate") {
        const idx = await caches.match("./index.html");
        if (idx) return idx;
      }
      throw err;
    }
  })());
});
