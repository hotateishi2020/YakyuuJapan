import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from tool_refresh_club_streaks import batting_log_maxima,pitching_log_maxima,normalize
from tool_refresh_npb_streaks import audit_steals

def page(rows):return '2026年度版<table>'+''.join('<tr>'+''.join('<td>'+str(c)+'</td>' for c in r)+'</tr>' for r in rows)+'</table>'
def batting(date,tokens,ab,hits,hr=0):
 r=['0']*26;r[0]=date;r[10]=str(ab);r[12]=str(hits);r[13]=str(hr);r[25]=tokens;return r
class ClubAuditTest(unittest.TestCase):
 def test_verified_same_day_order_resolves_tie_ambiguity(self):
  rows=[batting('4/1','',0,0),batting('4/2','',0,0)]
  rows[0][17]=rows[0][18]='1';rows[1][17]='1'
  def get(url):
   return '<a href="./Central/T/f/1_stat.htm">甲</a>' if 'fpnum' not in url else page(rows)
  player={'name':'甲','code':'T','sb':2,'cs':1,'official':'https://npb.jp/'}
  with self.assertRaises(ValueError):audit_steals(get,[player],2026)
  result,_=audit_steals(get,[player],2026,orders={'T|甲|4/1':{'sequence':[1,0],'sources':['https://example.test/game']}})
  self.assertEqual(result[0]['value'],1)
  self.assertIn('https://example.test/game',result[0]['sources'])
  with self.assertRaises(ValueError):
   audit_steals(get,[player],2026,orders={'T|甲|4/1':{'sequence':[1,1],'sources':['https://example.test/game']}})
 def test_batting_rbi_annotations_and_walk_only_game(self):
  rows=[batting('4/1','左本(2)',1,1,1),batting('4/2','四球',0,0),batting('4/3','右安',1,1)]
  annual=['0']*23
  for i,n in {1:3,2:3,5:2,8:1,15:1}.items():annual[i]=str(n)
  result=batting_log_maxima(page(rows),annual,2026)
  self.assertEqual(result['hit_games'],2)
  self.assertEqual(result['hit_pa'],1)
  self.assertEqual(result['onbase_pa'],3)
  self.assertEqual(result['hr_games'],1)
 def test_missing_game_fails_even_if_hit_total_matches(self):
  r=batting('4/1','右安',1,1);annual=['0']*23
  for i,n in {1:2,2:1,5:1}.items():annual[i]=str(n)
  with self.assertRaises(ValueError):batting_log_maxima(page([r]),annual,2026)
 def test_pitching_skips_no_decision_but_counts_unearned_runs(self):
  rows=[]
  for i,result in enumerate(['○','','○','●']):
   r=['0']*28;r[0]=f'4/{i+1}';r[8]=result;r[16]='1' if i==1 else '0';rows.append(r)
  annual=['0']*24
  for i,n in {1:4,2:2,3:1,21:1}.items():annual[i]=str(n)
  result=pitching_log_maxima(page(rows),annual,2026)
  self.assertEqual(result['wins'],2)
  self.assertEqual(result['scoreless_games'],2)
 def test_variant_names_normalized_only_for_matching(self):
  self.assertEqual(normalize('伊藤 大海'),normalize('伊藤大海'))

if __name__=='__main__':unittest.main()
