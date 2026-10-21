import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  for (final config in [
    ('regular-history', 1981, 540),
    ('regular-history-mlb', 2005, 630)
  ]) {
    test('${config.$1} covers all published team seasons with valid starts',
        () {
      final data =
          jsonDecode(File('data/${config.$1}.json').readAsStringSync());
      final rows = data['rows'] as List;
      expect(data['errors'], isEmpty);
      expect(rows, hasLength(config.$3));
      expect(rows.map((r) => r['year']).toSet(),
          {for (var y = config.$2; y <= 2025; y++) y});
      expect(rows.map((r) => '${r['year']}:${r['club_name']}').toSet(),
          hasLength(rows.length));
      for (final row in rows) {
        final games = row['lineup_game_count'] as int;
        expect(games, greaterThan(49));
        expect(row['batting_order'], hasLength(9));
        for (final group in row['batting_order']) {
          final counts = (group['players'] as List)
              .fold<int>(0, (n, p) => n + (p['count'] as int));
          expect(counts, games,
              reason: '${row['year']} ${row['club_name']} ${group['slot']}');
        }
        expect(row['source_url'], startsWith('https://'));
      }
    });
  }
}
