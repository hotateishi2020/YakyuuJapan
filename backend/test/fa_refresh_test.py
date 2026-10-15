import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('fa', Path(__file__).parents[1] / 'tool_refresh_fa_rights.py')
fa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fa)

class AcquisitionParserTest(unittest.TestCase):
    def test_old_format_excludes_existing_holders(self):
        document = fa.Tree('''<table><tr><th class="fateam">球団</th><td><table><tr>
        <td><span class="fa_mark">※</span><a href="/players/1.html">初回</a></td>
        <td><a href="/players/2.html">保有</a></td>
        <td><span class="fa_mark">＃</span><a href="/players/3.html">再取得</a></td>
        </tr></table></td><td><table><tr>
        <td><span class="fa_mark">※＊</span><a href="/players/4.html">特例</a></td>
        </tr></table></td></tr></table>''').root
        with patch.object(fa, 'fetch', return_value=document):
            rows = fa.official(2008)
        self.assertEqual([(r['player_key'], r['type']) for r in rows],
                         [('npb:1', 'domestic'), ('npb:3', 'domestic'), ('npb:4', 'international')])

    def test_current_format_only_acquisition_columns(self):
        document = fa.Tree('''<table><tr><th class="fateam">球団</th>
        <td><a href="/players/1.html">国内取得</a></td>
        <td><a href="/players/2.html">国内保有</a></td>
        <td><a href="/players/3.html">海外取得</a></td>
        <td><a href="/players/4.html">海外保有</a></td></tr></table>''').root
        with patch.object(fa, 'fetch', return_value=document):
            rows = fa.official(2025)
        self.assertEqual([r['player_key'] for r in rows], ['npb:1', 'npb:3'])

if __name__ == '__main__':
    unittest.main()
