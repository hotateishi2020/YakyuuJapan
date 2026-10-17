import 'dart:convert';
import 'dart:io';
import 'app/PlayerDetailSnapshot.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  print('選手詳細更新開始 $year');
  print(jsonEncode(await PlayerDetailSnapshot.refresh(year,
      playerIds:
          args.length > 1 ? args.skip(1).map(int.parse).toSet() : null)));
  exit(0);
}
