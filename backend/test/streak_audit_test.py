import collections
import pathlib
import sys
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from tool_refresh_npb_streaks import steal_run_bounds, parse_leaders
from tool_refresh_mlb_streaks import Runs, consume_plays, ordered_games, verify_events

def play(event, batter=1, runners=None, substitutions=None):
    return {'atBatIndex':0,'about':{'isComplete':True},'result':{'eventType':event},
            'matchup':{'batter':{'id':batter},'pitcher':{'id':9}},
            'runners':runners or [], 'playEvents':substitutions or []}
def runner(player, event, out=False, reason=None, index=0):
    return {'movement':{'isOut':out},'details':{'runner':{'id':player},'eventType':event,
            'playIndex':index,'movementReason':reason}}

class AuditTest(unittest.TestCase):
    def test_same_day_steal_order_bounds(self):
        self.assertEqual(steal_run_bounds([(2,0),(1,1),(1,0)]),(2,3))
        self.assertEqual(steal_run_bounds([(4,0),(0,1),(1,1)]),(4,4))
    def test_wrong_year_cannot_publish(self):
        with self.assertRaises(ValueError):parse_leaders('2025年度版 最高記録','hit_games',2026,'test')
    def test_steal_out_does_not_charge_other_advancing_runner(self):
        c=collections.Counter();r=Runs()
        consume_plays([play('caught_stealing_3b',runners=[
            runner(2,'caught_stealing_3b',True),runner(3,'caught_stealing_3b',reason='r_adv_play')])],r,c)
        self.assertEqual(c['hitting',2,'caughtStealing'],1)
        self.assertEqual(c['hitting',3,'caughtStealing'],0)
        self.assertEqual(c['hitting',1,'plateAppearances'],0)
    def test_error_can_still_be_official_caught_stealing_once(self):
        c=collections.Counter();r=Runs()
        consume_plays([play('caught_stealing_2b',runners=[
            runner(2,'caught_stealing_2b',reason='r_adv_play'),
            runner(2,'caught_stealing_2b',reason='r_caught_stealing_2b')])],r,c)
        self.assertEqual(c['hitting',2,'caughtStealing'],1)
    def test_force_out_does_not_retire_batter_and_hit_out_resets(self):
        r=Runs();c=collections.Counter()
        consume_plays([play('field_out',runners=[runner(1,'field_out',True)])],r,c)
        self.assertEqual(r.current['outs',9],1)
        consume_plays([play('force_out',runners=[runner(2,'force_out',True)])],r,c)
        self.assertEqual(r.current['outs',9],0)
        consume_plays([play('single',runners=[runner(1,'single',True)])],r,c)
        self.assertEqual(r.current['outs',9],0)
    def test_two_strike_substitute_pa_belongs_to_original_batter(self):
        r=Runs();c=collections.Counter()
        substitution={'details':{'eventType':'offensive_substitution'},'player':{'id':2},
            'count':{'strikes':2},'replacedPlayer':{'id':1}}
        consume_plays([play('strikeout',2,[runner(2,'strikeout',True)],[substitution])],r,c)
        self.assertEqual(c['hitting',1,'plateAppearances'],1)
        self.assertEqual(c['hitting',2,'plateAppearances'],0)
        self.assertEqual(r.best['strikeouts',9],1)
    def test_ties_and_cross_game_runs_keep_all_leaders(self):
        r=Runs();c=collections.Counter()
        for b in [1,2,1,2]:consume_plays([play('home_run',b)],r,c)
        self.assertEqual([x['value'] for x in r.leaders('hr_pa',{1:{'fullName':'A'},2:{'fullName':'B'}},2026)],[2,2])
        consume_plays([play('walk',1)],r,c)
        self.assertEqual(r.current['hit_pa',1],0)
    def test_inherited_walk_is_charged_to_previous_pitcher(self):
        r=Runs();c=collections.Counter()
        first=play('strikeout',runners=[runner(1,'strikeout',True)])
        second=play('walk',2);second['atBatIndex']=1
        second['matchup']['pitcher']['id']=10
        second['playEvents']=[{'details':{'eventType':'pitching_substitution'},
            'player':{'id':10},'count':{'balls':2,'strikes':1}}]
        consume_plays([first,second],r,c)
        self.assertEqual(c['pitching',9,'battersFaced'],2)
        self.assertEqual(c['pitching',10,'battersFaced'],0)
        self.assertEqual(r.current['strikeouts',9],0)
    def test_cancelled_and_duplicate_schedule(self):
        def game(pk,state):return {'gamePk':pk,'gameType':'R','officialDate':'2026-06-01','gameNumber':1,'status':{'abstractGameState':'Final','detailedState':state}}
        games=ordered_games({'dates':[{'games':[game(1,'Final'),game(1,'Final'),game(2,'Cancelled')]}]})
        self.assertEqual([g['gamePk'] for g in games],[1])
    def test_missing_event_fails_total_validation(self):
        result=verify_events(collections.Counter(),{'hitting':{1:{'hits':1}},'pitching':{}})
        self.assertEqual(result,[['hitting',1,'hits',1,0]])

if __name__=='__main__':unittest.main()
