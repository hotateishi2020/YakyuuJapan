import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import '../app/LogDetail.dart';

void main() {
  test('API読み込み・自動通知とユーザーの更新を分類する', () {
    for (final path in ['/predictions/part', '/season-schedule', '/videos', '/auth/me']) {
      expect(LogDetail.accessType(Request('GET', Uri.parse('https://example.test$path')),
          scheduled: false), 'ブラウザ処理');
    }
    expect(LogDetail.accessType(Request('POST', Uri.parse('https://example.test/predictions/ready')),
        scheduled: false), 'ブラウザ処理');
    expect(LogDetail.accessType(Request('POST', Uri.parse('https://example.test/auth/profile')),
        scheduled: false), '操作');
    expect(LogDetail.accessType(Request('GET', Uri.parse('https://example.test/fetchGamesNPB')),
        scheduled: true), 'サーバー処理');
  });
  test('初期読み込みはブラウザ処理、クリックによる画面選択は操作', () {
    expect(LogDetail.clientActionType('初期表示を読み込んだ'), 'ブラウザ処理');
    for (final action in LogDetail.clientActions.where((a) => a != '初期表示を読み込んだ')) {
      expect(LogDetail.clientActionType(action), '操作');
    }
    expect(LogDetail.clientActions, containsAll(['タイトルタブを開いた', '予想タブを開いた', '動画タブを開いた']));
  });

  test('接続元IPとブラウザ・端末を記録する', () {
    final info = LogDetail.clientInfo(Request('GET', Uri.parse('https://example.test/'), headers: {
      'x-forwarded-for': '203.0.113.8, 10.0.0.1',
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/130.0 Safari/537.36 Edg/130.0',
    }));
    expect(info['ip_address'], '203.0.113.8');
    expect(info['browser'], 'Edge');
    expect(info['device_type'], 'PC');
    final mobile = LogDetail.clientInfo(Request('GET', Uri.parse('https://example.test/'), headers: {
      'user-agent': 'Mozilla/5.0 (iPhone) CriOS/130 Mobile Safari/604',
    }));
    expect(mobile['browser'], 'Chrome');
    expect(mobile['device_type'], '携帯');
    final unknown = LogDetail.clientInfo(Request('GET', Uri.parse('https://example.test/')));
    expect(unknown['device_type'], '不明');
    expect(unknown['ip_address'], '');
  });
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
