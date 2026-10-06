import 'dart:js_interop';

import 'package:web/web.dart';

void bindPageVisibility(void Function() onVisible) {
  document.addEventListener(
    'visibilitychange',
    (Event _) {
      if (document.visibilityState == 'visible') onVisible();
    }.toJS,
  );
}
