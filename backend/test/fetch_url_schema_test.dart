import 'package:test/test.dart';

import '../app/FetchURL.dart';

void main() {
  test('schema ensure waiters do not block initial display forever', () {
    expect(FetchURL.schemaEnsureTimeout, const Duration(seconds: 8));
  });

  test('経歴の他リーグ球団は新人資格の対象外として拾う', () {
    final clubs = [
      CareerClub(id: 1, league: 1, shortName: '巨人', fullName: '読売ジャイアンツ'),
      CareerClub(id: 137, league: 4, shortName: 'ジャイアンツ', fullName: 'サンフランシスコ・ジャイアンツ'),
      CareerClub(id: 146, league: 4, shortName: 'マーリンズ', fullName: 'マイアミ・マーリンズ'),
      CareerClub(id: 8, league: 2, shortName: '西武', fullName: '埼玉西武ライオンズ'),
      CareerClub(id: 90, league: 5, shortName: '統一', fullName: '統一ライオンズ'),
    ];
    expect(FetchURL.outsideClubIds('マーリンズ - ジャイアンツ', clubs), [146, 137]);
    expect(FetchURL.outsideClubIds('ヘリテージ高 - 米マイナー', clubs), isEmpty);
    expect(FetchURL.outsideClubIds('中国文化大 - 台湾・統一', clubs), [90]);
    expect(FetchURL.outsideClubIds('西武', clubs), isEmpty);
  });
}
