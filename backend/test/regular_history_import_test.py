import importlib.util
from pathlib import Path
import unittest
from datetime import date, timedelta
spec=importlib.util.spec_from_file_location('importer',Path(__file__).parents[1]/'tool_refresh_regular_history.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class RegularImportTest(unittest.TestCase):
    def test_postseason_excluded_and_starting_slots_counted(self):
        def game(day,name):
            cells=[f'{day.year}/{day.month}/{day.day}']+[f'{p}{name}{p}' for p in range(1,10)]
            return '<tr>'+''.join('<td>'+c+'</td>' for c in cells)+'</tr>'
        body='<table>'+''.join(game(date(2025,3,1)+timedelta(days=n),'選手') for n in range(60))
        body+='<tr><td colspan="11">クライマックスシリーズ</td></tr>'+game(date(2025,10,1),'別選手')+'</table>'
        row=module.parse(body,2025,'阪神','https://sta-men.jp/2025tigers.html')
        self.assertEqual(row['game_count'],60)
        self.assertEqual(len(row['batting_order']),9)
        self.assertEqual(row['batting_order'][0]['players'][0]['count'],60)
        self.assertEqual(row['positions'][0]['players'][0]['name'],'選手1')
        self.assertNotIn('別選手',str(row))
    def test_incomplete_season_is_not_published(self):
        with self.assertRaises(ValueError):module.parse('<html></html>',2025,'阪神','url')
    def test_decoy_and_replacement_are_not_concatenated_as_one_name(self):
        parser=module.Rows()
        parser.feed('<tr><td><span class="tei">7斉藤</span><br>7出口</td></tr>')
        self.assertEqual(parser.rows, [['7出口']])
if __name__=='__main__':unittest.main()
