import importlib.util
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).parents[1]))
import tool_enrich_regular_archive as archive


class RegularArchiveTest(unittest.TestCase):
    def test_historical_mixed_roles_keep_observed_starts_without_invented_innings(self):
        row = {'year': 2004, 'club_name': 'ソフトバンク', 'positions': [], 'batting_order': []}
        stats = {'pitching_stats': [
            {'name': '和田毅', 'player_key': 'w', 'starts': 18, 'appearances': 19,
             'total_outs': 385, 'throws': '左', 'holds': None}],
            'batting_stats': [{'name': '松中信彦', 'player_key': 'm', 'pa': 577}]}
        archive.apply(row, stats, 'https://example.test/2004')
        pitcher = row['pitching_workload'][0]
        self.assertEqual(pitcher['starts'], 18)
        self.assertEqual(pitcher['relief_appearances'], 1)
        self.assertNotIn('starter_outs', pitcher)
        self.assertNotIn('relief_outs', pitcher)
        self.assertIsNone(pitcher['holds'])

    def test_official_totals_must_agree(self):
        row = {'year': 2024, 'club_name': '球団', 'official_stat_sources': ['official'],
               'pitching_stats': [{'name': '投手', 'appearances': 20}]}
        with self.assertRaisesRegex(ValueError, 'appearances mismatch'):
            archive.apply(row, {'pitching_stats': [{'name': '投手', 'appearances': 21}]}, 'archive')

    def test_foreign_initial_is_resolved_only_when_unique(self):
        row = {'club_name': '球団', 'batting_order': [], 'positions': [
            {'slot': 'P', 'total': 10, 'players': [{'name': 'グーリン', 'count': 10}]}],
            'pitching_stats': [{'name': 'L.グーリン', 'player_key': 'g',
                               'appearances': 10, 'total_outs': 150}]}
        archive.normalize_groups(row)
        self.assertEqual(row['unresolved_names'], [])
        self.assertEqual(row['pitching_workload'][0]['starter_outs'], 150)

if __name__ == '__main__': unittest.main()
