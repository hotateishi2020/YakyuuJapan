(() => {
  const current = '1b1ba5a0a7949e2865fbb785b355dd5574c32377abcc57ebf7de7bcf501e9a64';
  // Replaced only by tool/build_web.sh; IDE builds use reload-on-save.
  if (current.startsWith('__APP_')) return;
  let checking = false;
  let reloading = false;
  async function check() {
    if (checking || reloading || document.hidden) return;
    checking = true;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch(new URL('app_version.json?t=' + Date.now(), document.baseURI), {
        cache: 'no-store', signal: controller.signal,
      });
      if (!response.ok) return;
      const {build} = await response.json();
      if (typeof build !== 'string' || !/^[a-f0-9]{64}$/.test(build) || build === current) return;
      // Stop old Flutter offline caches from serving the previous application.
      // Cache APIs can be unavailable in restricted browsing modes. A cleanup
      // failure must not prevent the application from updating.
      try {
        const registrations = await navigator.serviceWorker?.getRegistrations() || [];
        for (const registration of registrations) {
          if (registration.scope === new URL('.', document.baseURI).href) await registration.unregister();
        }
      } catch (_) {}
      try {
        if ('caches' in window) for (const name of await caches.keys()) {
          if (['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'].includes(name)) await caches.delete(name);
        }
      } catch (_) {}
      reloading = true;
      location.reload();
    } catch (_) {
      // Keep the current application usable while offline or during deployment.
    } finally {
      clearTimeout(timeout);
      checking = false;
    }
  }
  setInterval(check, 20000);
  window.addEventListener('focus', check);
  window.addEventListener('online', check);
  document.addEventListener('visibilitychange', check);
  check();
})();
