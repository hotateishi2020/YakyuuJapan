import 'dart:convert';
import 'dart:io';
import 'app/AllStarPositions.dart';

Future<void> main() async {
  final data = jsonDecode(File('data/allstar_history.json').readAsStringSync());
  await refreshAllStarPositions(
      [for (final row in data['players']) Map<String, dynamic>.from(row)]);
}
