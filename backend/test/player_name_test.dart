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
  });
}
