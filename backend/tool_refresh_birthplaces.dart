import 'dart:io';
import 'app/RosterBirthplaces.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  print('出身地補完開始 $year');
  final count = await refreshRosterBirthplaces(year);
  print('出身地補完: $count 球団');
  exit(0);
}
