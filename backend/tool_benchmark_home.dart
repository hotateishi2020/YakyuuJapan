import 'dart:convert';
import 'dart:io';
import 'index.dart' as server;

Future<void> main() async {
  for (var attempt = 0; attempt < 2; attempt++) {
    final watch = Stopwatch()..start();
    final data = await server.readHomeDashboard();
    print(jsonEncode({'attempt': attempt + 1,'ms': watch.elapsedMilliseconds,
      'games': (data['games'] as List? ?? []).length,
      'heroes': (data['heroes'] as List? ?? []).length,
      'birthdays': (data['birthdays'] as List? ?? []).length}));
  }
  exit(0);
}
