import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/MlbSeasonPositions.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  print('MLBポジション更新開始 $year');
  print(jsonEncode(await Postgres.withConnection(
      (conn) => refreshMlbSeasonPositions(conn, year))));
  exit(0);
}
