import 'dart:io';
import 'app/FetchMLB.dart';

Future<void> main() async {
  await FetchMLB.refreshNearSchedule();
  print('MLB当日〜10日後の日程再確認と表示スナップショット更新が完了しました');
  exit(0);
}
