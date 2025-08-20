import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class Env {
	static String baseUrl() {
		if (kIsWeb) {
			return 'http://127.0.0.1:5050';
		}
		try {
			if (Platform.isAndroid) return 'http://10.0.2.2:5050';
			if (Platform.isIOS || Platform.isMacOS) return 'http://127.0.0.1:5050';
			if (Platform.isWindows || Platform.isLinux) return 'http://127.0.0.1:5050';
		} catch (_) {}
		return 'http://127.0.0.1:5050';
	}
} 