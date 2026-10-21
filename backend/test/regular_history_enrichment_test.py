import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'enrichment', Path(__file__).parents[1] / 'tool_enrich_regular_history.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RegularEnrichmentTest(unittest.TestCase):
    def test_aliases_merge_counts_without_merging_same_surname_players(self):
        def group(slot, entries):
            return {'slot': slot, 'total': 100, 'players': [
                {'name': name, 'count': count} for name, count in entries]}
        row = {'club_name': 'ソフトバンク',
               'batting_stats': [
                   {'name': name, 'player_key': key, 'pa': pa}
                   for name, key, pa in [
                       ('松田宣浩', 'm', 500), ('松田遼馬', 'r', 0),
                       ('内川聖一', 'u', 400), ('田中一郎', 'a', 100),
                       ('田中二郎', 'b', 100)]],
               'positions': [
                   group('3B', [('松田', 20), ('松田宣', 60)]),
                   group('1B', [('内川', 30), ('内川聖一', 40)]),
                   group('LF', [('田中', 10)])],
               'batting_order': []}
        module.normalize_groups(row)
        self.assertEqual(row['positions'][0]['players'][0]['name'], '松田宣浩')
        self.assertEqual(row['positions'][0]['players'][0]['count'], 80)
        self.assertEqual(row['positions'][1]['players'][0]['count'], 70)
        self.assertEqual(row['unresolved_names'], ['田中'])

    def test_mixed_pitching_innings_are_not_estimated(self):
        row = {'club_name': '球団', 'batting_order': [],
               'positions': [{'slot': 'P', 'total': 100, 'players': [
                   {'name': '先発', 'count': 20}, {'name': '兼任', 'count': 5}]}],
               'pitching_stats': [
                   {'name': name, 'player_key': name, 'appearances': games,
                    'total_outs': total}
                   for name, games, total in [
                       ('先発', 20, 400), ('兼任', 30, 200), ('救援', 50, 150)]]}
        module.normalize_groups(row)
        pitchers = {p['name']: p for p in row['pitching_workload']}
        self.assertEqual(pitchers['先発']['starter_outs'], 400)
        self.assertEqual(pitchers['救援']['relief_outs'], 150)
        self.assertNotIn('starter_outs', pitchers['兼任'])
        self.assertNotIn('relief_outs', pitchers['兼任'])

    def test_innings_fractions_are_outs_not_decimals(self):
        self.assertEqual(module.outs('125 1/3'), 376)
        self.assertEqual(module.outs('0.2'), 2)
        self.assertEqual(module.outs('2/3'), 2)


if __name__ == '__main__':
    unittest.main()
