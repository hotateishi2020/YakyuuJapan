import 'dart:io';
import 'app/GameBench.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection(GameBench.ensure);
  print('Verified t_game_bench');
  exit(0);
}
