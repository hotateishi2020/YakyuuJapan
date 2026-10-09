import 'package:test/test.dart';
import '../app/PlayerName.dart';

void main() {
  test('parse abbreviated MLB name', () {
    final p = parsePlayerName('J.チョウリオ');
    expect(p.initial, 'J');
    expect(p.surname, 'チョウリオ');
  });

  test('match abbr to full katakana name with stored initial', () {
    expect(
      playerNameMatches(
        query: 'J.チョウリオ',
        nameFull: 'ジャクソン・チョウリオ',
        nameLast: 'ジャクソン・チョウリオ',
        storedInitial: 'J',
      ),
      isTrue,
    );
  });

  test('match abbr to same abbr roster row', () {
    expect(
      playerNameMatches(
        query: 'J.チョウリオ',
        nameFull: 'J.チョウリオ',
        storedInitial: '',
      ),
      isTrue,
    );
  });

  test('pickBestPlayerId prefers matching initial', () {
    final id = pickBestPlayerId(
      query: 'J.チョウリオ',
      candidates: [
        (id: 1, nameFull: 'マイク・チョウリオ', nameLast: 'マイク・チョウリオ', initial: 'M'),
        (id: 2, nameFull: 'ジャクソン・チョウリオ', nameLast: 'ジャクソン・チョウリオ', initial: 'J'),
      ],
    );
    expect(id, 2);
  });

  test('C.セール matches クリス・セール as the same pitcher', () {
    expect(
      playerNameMatches(
        query: 'C.セール',
        nameFull: 'クリス・セール',
        nameLast: 'セール',
        storedInitial: 'C',
      ),
      isTrue,
    );
    expect(
      playerNameMatches(
        query: 'クリス・セール',
        nameFull: 'C.セール',
        nameLast: 'セール',
        storedInitial: 'C',
      ),
      isTrue,
    );
  });

  test('match surname-only live name to full MLB name', () {
    expect(
      playerNameMatches(query: 'モンゴメリー', nameFull: 'ブレーデン・モンゴメリー'),
      isTrue,
    );
    expect(
      playerNameMatches(query: 'B.モンゴメリー', nameFull: 'ブレーデン・モンゴメリー'),
      isTrue,
    );
    expect(
      playerNameMatches(query: 'C.マイドロス', nameFull: 'チェース・マイドロス'),
      isTrue,
    );
    expect(
      playerNameMatches(query: 'ブレーデン・モンゴメリー', nameFull: 'コルソン・モンゴメリー'),
      isFalse,
    );
    expect(
      playerNameMatches(query: 'コルソン・モンゴメリー', nameFull: 'ブレーデン・モンゴメリー'),
      isFalse,
    );
    expect(
      playerNameMatches(query: 'ヘーゲン・スミス', nameFull: 'C.スミス', storedInitial: 'C'),
      isFalse,
    );
    expect(
      playerNameMatches(query: 'C.スミス', nameFull: 'ヘーゲン・スミス', nameLast: 'ヘーゲン・スミス', storedInitial: 'H'),
      isFalse,
    );
    expect(
      playerNameMatches(query: 'C.スミス', nameFull: 'ケード・スミス', nameLast: 'ケード・スミス', storedInitial: 'C'),
      isTrue,
    );
    expect(
      playerNameMatches(query: 'H.スミス', nameFull: 'ヘーゲン・スミス', nameLast: 'ヘーゲン・スミス', storedInitial: 'H'),
      isTrue,
    );
    expect(
      playerNameMatches(
        query: 'C.モンゴメリー',
        nameFull: 'ブレーデン・モンゴメリー',
        nameLast: 'ブレーデン・モンゴメリー',
        storedInitial: 'C',
      ),
      isFalse,
    );
  });

  test('同姓のモンゴメリーはフルネームの行を選ぶ', () {
    final candidates = [
      (id: 5710, nameFull: 'C.モンゴメリー', nameLast: 'C.モンゴメリー', initial: 'C'),
      (id: 5983, nameFull: 'ブレーデン・モンゴメリー', nameLast: 'ブレーデン・モンゴメリー', initial: 'C'),
      (id: 5984, nameFull: 'コルソン・モンゴメリー', nameLast: 'コルソン・モンゴメリー', initial: 'C'),
    ];
    List<({int id, String nameFull, String nameLast, String initial})> matching(String query) {
      return [
        for (final c in candidates)
          if (playerNameMatches(query: query, nameFull: c.nameFull, nameLast: c.nameLast, storedInitial: c.initial)) c,
      ];
    }

    expect(pickBestPlayerId(query: 'ブレーデン・モンゴメリー', candidates: matching('ブレーデン・モンゴメリー')), 5983);
    expect(pickBestPlayerId(query: 'コルソン・モンゴメリー', candidates: matching('コルソン・モンゴメリー')), 5984);
    expect(correctedNameInitial('ブレーデン・モンゴメリー', 'C'), 'B');
    expect(correctedNameInitial('コルソン・モンゴメリー', 'C'), isNull);
  });
}
