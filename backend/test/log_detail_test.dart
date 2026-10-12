import 'package:test/test.dart';

import '../app/LogDetail.dart';

void main() {
  test('スタックの先頭フレームから関数とファイルと行を取る', () {
    const stack = '''
#0 updatePrediction (package:Yakyuu_Japan/backend/app/prediction.dart:125:8)
#1 tryCatchAPI (package:Yakyuu_Japan/backend/index.dart:10:5)
''';
    final frame = LogDetail.stackFrame(stack);
    expect(frame['function_name'], 'updatePrediction');
    expect(frame['file_name'], 'prediction.dart');
    expect(frame['line_number'], '125');
  });

  test('画面操作の名前から画面名を決める', () {
    expect(LogDetail.screenOf('mlbタブを開いた'), 'MLB');
    expect(LogDetail.screenOf('年度を変更した'), '年度');
    expect(LogDetail.screenOf(''), '');
  });

  test('発生日時は日本時間で出す', () {
    expect(LogDetail.formatJst(DateTime.utc(2026, 10, 12, 12, 35, 4)), '2026-10-12 21:35:04');
    expect(LogDetail.formatJst('2026-10-12T03:00:00Z'), '2026-10-12 12:00:00');
  });
}
