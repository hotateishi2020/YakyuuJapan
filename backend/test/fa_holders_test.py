import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tool_refresh_fa_holders import holders
from tool_refresh_fa_rights import Tree

class HolderParserTest(unittest.TestCase):
    def test_includes_retained_rights_but_excludes_exercised(self):
        doc = Tree('''<table><tr><th class="fateam">球団</th>
        <td><a href="/bis/players/1.html">新規国内</a></td>
        <td><a href="/bis/players/2.html">保有国内</a></td>
        <td><a href="/bis/players/3.html">新規海外</a></td>
        <td><a href="/bis/players/4.html">行使済み</a></td>
        </tr></table>''').root
        rows = holders(doc, 2025, {'4'})
        self.assertEqual([(r['player_key'], r['type']) for r in rows],
                         [('npb:1','domestic'),('npb:2','domestic'),('npb:3','international')])

if __name__ == '__main__': unittest.main()
