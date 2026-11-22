{{flutter_js}}
{{flutter_build_config}}

// Hostinger CDN kept serving a week-old main.dart.js after deploys.
// Bust that URL and drop any previously registered Flutter service worker.
(function () {
  const cacheTag = '20261104a';
  try {
    const builds = _flutter.buildConfig && _flutter.buildConfig.builds;
    if (Array.isArray(builds)) {
      for (const build of builds) {
        if (build && typeof build.mainJsPath === 'string') {
          const base = build.mainJsPath.split('?')[0];
          build.mainJsPath = base + '?v=' + cacheTag;
        }
      }
    }
  } catch (_) {}

  if ('serviceWorker' in navigator) {
    const appScope = new URL('./', document.baseURI).href;
    const oldWorker = new URL('flutter_service_worker.js', appScope).href;
    navigator.serviceWorker.getRegistrations().then(async (regs) => {
      for (const reg of regs) {
        const workers = [reg.active, reg.waiting, reg.installing];
        if (reg.scope === appScope && workers.some((worker) =>
          worker && worker.scriptURL.split('?')[0] === oldWorker)) {
          await reg.unregister();
        }
      }
    }).catch(() => {
      // A browser storage restriction must not prevent app startup.
    });
  }
})();

// The renderer ships in build/web/canvaskit. Load it from the same host so
// startup does not depend on reaching Google's separate CDN.
_flutter.loader.load({
  config: {
    hostElement: document.getElementById('sanad-app'),
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
  },
});
