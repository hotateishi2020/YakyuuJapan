import 'dart:convert';
import 'app/GameBroadcasts.dart';
Future<void> main() async {
  for (final prefecture in ['佐賀県','長野県']) {
    final rows = await readGameBroadcasts(DateTime(2026,10,27),'ソフトバンク','DeNA',prefecture);
    print(jsonEncode({'prefecture':prefecture,'broadcasts':rows}));
  }
}
