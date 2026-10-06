export 'browser_cookie_stub.dart'
    if (dart.library.html) 'browser_cookie_web.dart'
    if (dart.library.js_interop) 'browser_cookie_web.dart';
