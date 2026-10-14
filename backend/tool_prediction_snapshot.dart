import 'dart:io';

import 'app/PredictionSnapshot.dart';
import 'tools/Postgres.dart';

/// デプロイ前/初回導入時の登録。画面アクセスによる暗黙の再集計は行わない。
Future<void> main() async {
  final conn = await Postgres.acquire();
  try {
    await PredictionSnapshot.refresh(conn, allYears: true);
    stdout.writeln('予想表示用テーブルの初回登録が完了しました。');
  } finally {
    await conn.close();
  }
}
