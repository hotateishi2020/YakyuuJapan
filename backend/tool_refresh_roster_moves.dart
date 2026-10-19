import 'dart:convert';
import 'dart:io';
import 'app/RosterMoves.dart';

Future<void> main(List<String> args) async {
  try {
    print(jsonEncode(await RosterMoves.refresh(
        args.isEmpty ? DateTime.now().year : int.parse(args.first))));
    exit(0);
  } catch (e) {
    stderr.writeln('入退団更新失敗: $e');
    exit(1);
  }
}
