import 'package:test/test.dart';
import '../app/PlayerArt.dart';
import '../app/PlayerArtSchedule.dart';

void main() {
  final p = <String, dynamic>{
    'id': 1,
    'name_full': '選手',
    'id_team': 7,
    'uniform_number': '00'
  };
  test(
      'transfer and uniform changes invalidate artwork but unrelated stats do not',
      () {
    final original = PlayerArt.fingerprint(p);
    expect(PlayerArt.fingerprint({...p, 'id_team': 8}), isNot(original));
    expect(
        PlayerArt.fingerprint({...p, 'uniform_number': '0'}), isNot(original));
    expect(PlayerArt.fingerprint({...p, 'year_retire': 2026}), isNot(original));
    expect(PlayerArt.fingerprint({...p, 'flg_delete': true}), isNot(original));
    expect(PlayerArt.fingerprint({...p, 'batting_average': .3}), original);
  });
  test('research rejects private, lookalike and credential-bearing source URLs',
      () {
    expect(
        PlayerArtSchedule.sourceAllowed('https://ja.wikipedia.org/wiki/柳田悠岐'),
        isTrue);
    expect(
        PlayerArtSchedule.sourceAllowed(
            'https://www.softbankhawks.co.jp/team/player/'),
        isTrue);
    for (final url in [
      'http://npb.jp/a',
      'https://127.0.0.1/a',
      'https://npb.jp.evil.example/a',
      'https://user:pass@npb.jp/a',
      'https://npb.jp:8080/a'
    ]) {
      expect(PlayerArtSchedule.sourceAllowed(url), isFalse, reason: url);
    }
  });
  test('deleted and retired players cannot enter automatic image queue', () {
    expect(PlayerArt.active(p), isTrue);
    expect(PlayerArt.active({...p, 'flg_delete': true}), isFalse);
    expect(
        PlayerArt.active({...p, 'year_retire': DateTime.now().year}), isFalse);
  });
  test('unknown numbers use verified research without losing leading zeroes',
      () {
    final facts = <Map<String, dynamic>>[
      {'category': 'number', 'value': '012'}
    ];
    expect(
        PlayerArtSchedule.resolvedPlayer(
            {...p, 'uniform_number': null}, facts)['uniform_number'],
        '012');
    expect(() => PlayerArtSchedule.resolvedPlayer(p, facts), throwsStateError);
    expect(
        () => PlayerArtSchedule.resolvedPlayer(
            {...p, 'uniform_number': null}, []),
        throwsStateError);
  });
}
