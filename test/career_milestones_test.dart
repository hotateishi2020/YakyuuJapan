import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/achievement_priority.dart';
import 'package:Yakyuu_Japan/View/achievement_badge.dart';
import 'package:Yakyuu_Japan/View/strength_research.dart';

Map<String, dynamic> milestone(int count,
        {String scope = 'NPB', String metric = '本塁打', int year = 2026}) =>
    {
      'label': '$scope 通算$count$metric',
      'kind': 'milestone',
      'year': year,
      'source': 'https://example.test/$count'
    };

void main() {
  test('功績の数字は途中で改行せず3行以内に収める', () {
    for (final number in ['300', '2000', '1,000', '３００', '0.300']) {
      final caption = 'NPB 通算$number本塁打';
      final text = achievementBadgeEngraving(caption);
      expect(text, contains(number));
      expect(text.replaceAll('\n', ''), caption);
      expect(text.split('\n').length, lessThanOrEqualTo(3));
    }
  });

  test('最上位の通算功績に下位の評価を集約し、出典を維持する', () {
    final original = [
      for (final n in [100, 200, 300, 400]) milestone(n)
    ];
    final compact = consolidateCareerMilestones(original);
    expect(compact.single['label'], 'NPB 通算400本塁打');
    expect(compact.single['source'], original.last['source']);
    expect(achievementValue(compact.single),
        original.fold<double>(0, (sum, a) => sum + achievementValue(a)));
    expect(achievementBadgeSize(compact.single),
        greaterThan(achievementBadgeSize(original.last)));
    expect(original.last.containsKey('consolidated_value'), isFalse);
  });

  test('NPB・MLBと異なる指標を分離し、単年功績は残す', () {
    final compact = consolidateCareerMilestones([
      milestone(300),
      milestone(400),
      milestone(100, scope: 'MLB'),
      for (final metric in ['勝', '安打', 'セーブ', '奪三振']) ...[
        milestone(1000, metric: metric),
        milestone(2000, metric: metric),
      ],
      {'label': 'シーズン100打点', 'kind': 'milestone', 'year': 2025},
      {'label': 'シーズン100打点', 'kind': 'milestone', 'year': 2026},
    ]);
    expect(compact.length, 8);
    expect(compact.where((a) => '${a['label']}'.contains('1000')), isEmpty);
    expect(compact.where((a) => a['label'] == 'MLB 通算100本塁打'), hasLength(1));
  });

  testWidgets('功績タブは表示年度までの最上位のみを表示する', (tester) async {
    for (final year in [2025, 2026]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: StrengthAchievements(year: year, team: {
          'id_team': 1,
          'roster': [
            {
              'name': '選手',
              'player_key': 'p1',
              'achievements': [
                milestone(200, year: 2024),
                milestone(300, year: 2025),
                milestone(400, year: 2026),
              ],
            }
          ],
        }),
      )));
      await tester.pumpAndSettle();
      final badge =
          tester.widget<AchievementBadge>(find.byType(AchievementBadge));
      expect(
          badge.achievement['label'], 'NPB 通算${year == 2025 ? 300 : 400}本塁打');
      expect(tester.takeException(), isNull);
    }
  });
}
