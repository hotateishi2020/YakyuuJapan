import 'dart:convert';
import 'dart:io';
import 'app/GameSeasonStats.dart';

Future<void> main(List<String> args) async {
  final result = await GameSeasonStats.refresh(int.parse(args.firstOrNull ?? '2026'));
  stdout.writeln(jsonEncode(result));
  exit((result['errors'] as List? ?? []).isNotEmpty ? 1 : 0);
}
