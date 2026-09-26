// Shared cache helper for CrispChess engine downloads.
// Uses Cache Storage API for persistent caching across sessions.

async function cachedFetch(url, cacheName) {
  cacheName = cacheName || 'crispchess-engines';

  // Try cache first
  try {
    const cache = await caches.open(cacheName);
    const cached = await cache.match(url);
    if (cached) {
      console.log('[Cache] Hit: ' + url.substring(url.lastIndexOf('/') + 1));
      return cached;
    }
  } catch (e) {
    console.log('[Cache] Storage unavailable: ' + e);
  }

  // Fetch from network
  console.log('[Cache] Miss — downloading: ' + url.substring(url.lastIndexOf('/') + 1));
  const response = await fetch(url);
  if (!response.ok) throw new Error('HTTP ' + response.status + ' for ' + url);

  // Store in cache (clone response since it can only be consumed once)
  try {
    const cache = await caches.open(cacheName);
    await cache.put(url, response.clone());
    console.log('[Cache] Stored: ' + url.substring(url.lastIndexOf('/') + 1));
  } catch (e) {
    console.log('[Cache] Store failed: ' + e);
  }

  return response;
}

globalThis.cachedFetch = cachedFetch;
