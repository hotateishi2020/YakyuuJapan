import 'package:test/test.dart';
import '../app/PlayerIdentityName.dart';
import '../app/PlayerName.dart';

void main() {
  test('リーとライリーを姓の末尾一致で同一人物にしない', () {
    expect(playerNameMatches(query:'リー',nameFull:'オースティン・ライリー'),isFalse);
    expect(playerNameMatches(query:'D.リー',nameFull:'オースティン・ライリー',storedInitial:'A'),isFalse);
    expect(playerNameMatches(query:'B.リー',nameFull:'ブルックス・リー',storedInitial:'B'),isTrue);
    expect(playerNameMatches(query:'ブルックス・リー',nameFull:'タジ・ブラッドリー'),isFalse);
  });
  test('字体・アクセント・全角・Markdownの装飾を同一視し原文は保持', () {
    expect(playerIdentityKey('髙橋 光成'), playerIdentityKey('高橋光成'));
    expect(playerIdentityKey('**Kiké Hernández**'),
        playerIdentityKey('Kike Hernandez'));
    expect(playerIdentityKey('Ｋｉｋｅ́ Ｈｅｒｎａ́ｎｄｅｚ'),
        playerIdentityKey('Kike Hernandez'));
    expect(playerIdentityKey('Ｍ．マチャド'), playerIdentityKey('M.マチャド'));
  });
  test('登録済みの本名・愛称を順に照合', () {
    const patterns = [
      'マニー・マチャド',
      'M.マチャド',
      'Manny Machado',
      'Manuel Arturo Machado',
      'マチャド'
    ];
    for (final name in patterns) {
      expect(matchesPlayerPatterns(name, patterns), isTrue);
    }
    expect(matchesPlayerPatterns('Andrés Machado', patterns), isFalse);
    expect(
        matchesPlayerPatterns(
            'キケ・ヘルナンデス', ['エンリケ・ヘルナンデス', 'キケ・ヘルナンデス', 'Kiké Hernández']),
        isTrue);
  });
  test('同姓・同イニシャルの候補は短い名前を勝手に選ばない', () {
    const candidates = [
      (id: 1, nameFull: 'ケード・スミス', nameLast: 'スミス', initial: 'C'),
      (id: 2, nameFull: 'キャメロン・スミス', nameLast: 'スミス', initial: 'C')
    ];
    expect(pickBestPlayerId(query: 'C.スミス', candidates: candidates), isNull);
    expect(pickBestPlayerId(query: 'スミス', candidates: candidates), isNull);
    expect(playerNameMatches(query: '高橋光', nameFull: '高橋光成'), isFalse);
  });
  test('名前の長さによらず同名IDが複数なら未確定にする', () {
    expect(
        pickBestPlayerId(query: '高橋光成', candidates: [
          (id: 1, nameFull: '高橋光成', nameLast: '高橋', initial: ''),
          (id: 2, nameFull: '髙橋 光成', nameLast: '髙橋', initial: ''),
        ]),
        isNull);
  });
  test('MLB公式IDで日本語化し英語の識別キーは変更しない', () {
    final result = localizePlayerPayload({
      'players': [
        {
          'source_player_id': '592518',
          'name': 'Manny Machado',
          'player_key': 'mlb:592518'
        },
        {
          'name': 'Manuel Arturo Machado',
          'player_key': 'name:manuelarturomachado'
        },
        {'source_player_id': '600921', 'name': 'Andrés Machado'}
      ]
    }, {
      '592518': 'マニー・マチャド'
    }, {
      playerIdentityKey('Manuel Arturo Machado'): 'マニー・マチャド'
    });
    expect(result['players'][0]['name'], 'マニー・マチャド');
    expect(result['players'][0]['player_key'], 'mlb:592518');
    expect(result['players'][1]['name'], 'マニー・マチャド');
    expect(result['players'][2]['name'], 'Andrés Machado');
  });
}
