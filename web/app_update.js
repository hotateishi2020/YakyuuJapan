(() => {
  const current = '__APP_BUILD_ID__';
  // Replaced only by tool/build_web.sh; IDE builds use reload-on-save.
  if (current.startsWith('__APP_')) return;
  let checking = false;
  async function check() {
    if (checking || document.hidden) return;
    checking = true;
    try {
      const response = await fetch('app_version.json?t=' + Date.now(), {cache: 'no-store'});
      if (!response.ok) return;
      const {build} = await response.json();
      if (typeof build !== 'string' || !/^[a-f0-9]{64}$/.test(build) || build === current) return;
      // Stop old Flutter offline caches from serving the previous application.
      const registrations = await navigator.serviceWorker?.getRegistrations() || [];
      for (const registration of registrations) {
        if (registration.scope === new URL('.', document.baseURI).href) await registration.unregister();
      }
      if ('caches' in window) for (const name of await caches.keys()) {
        if (['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'].includes(name)) await caches.delete(name);
      }
      location.reload();
    } catch (_) {
      // Keep the current application usable while offline or during deployment.
    } finally { checking = false; }
  }
  setInterval(check, 20000);
  window.addEventListener('focus', check);
  document.addEventListener('visibilitychange', check);
})();
