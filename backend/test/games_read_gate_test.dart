import 'package:test/test.dart';

import '../app/GamesReadGate.dart';

void main() {
  test('更新日時が同じなら前回の試合結果を使い、変わっていればSQLをやり直す', () {
    final stamp = GamesReadGate.token(DateTime.utc(2026, 10, 9, 2, 30), 12);
    expect(
      GamesReadGate.reuse(cachedBody: '{"games":[]}', previousRevision: stamp, revision: stamp),
      isTrue,
    );
    final next = GamesReadGate.token(DateTime.utc(2026, 10, 9, 2, 31), 12);
    expect(
      GamesReadGate.reuse(cachedBody: '{"games":[]}', previousRevision: stamp, revision: next),
      isFalse,
    );
    expect(
      GamesReadGate.reuse(cachedBody: null, previousRevision: stamp, revision: stamp),
      isFalse,
    );
    expect(
      GamesReadGate.reuse(cachedBody: '{"games":[]}', previousRevision: null, revision: stamp),
      isFalse,
    );
  });

  test('件数が変わった削除も更新ありとして扱う', () {
    final before = GamesReadGate.token(DateTime.utc(2026, 10, 9, 2, 30), 12);
    final after = GamesReadGate.token(DateTime.utc(2026, 10, 9, 2, 30), 11);
    expect(before == after, isFalse);
  });
}
