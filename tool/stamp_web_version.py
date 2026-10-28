"""Stamp a successfully compiled web build with its content fingerprint."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'build/web'
digest = hashlib.sha256()
for path in sorted(root.rglob('*')):
    if path.is_file() and path.name not in {'app_version.json', 'flutter_service_worker.js'}:
        digest.update(str(path.relative_to(root)).encode())
        digest.update(path.read_bytes())
build = digest.hexdigest()
updater = root / 'app_update.js'
updater.write_text(updater.read_text().replace('__APP_BUILD_ID__', build))
(root / 'app_version.json').write_text(json.dumps({'build': build}))

index = root / 'index.html'
index.write_text(index.read_text().replace('src="app_update.js"', f'src="app_update.js?v={build}"').replace('src="flutter_bootstrap.js"', f'src="flutter_bootstrap.js?v={build}"'))

# The loader must request the new compiled application even when an older
# main.dart.js is still in the browser's HTTP cache.
bootstrap = root / 'flutter_bootstrap.js'
bootstrap.write_text(bootstrap.read_text().replace('"mainJsPath":"main.dart.js"', f'"mainJsPath":"main.dart.js?v={build}"'))
