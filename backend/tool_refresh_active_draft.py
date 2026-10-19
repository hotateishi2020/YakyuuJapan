"""Refresh completed active-player drafts from official NPB result pages."""
import json
import re
import subprocess
from html import unescape
from pathlib import Path

TEAMS = {'読売ジャイアンツ':'巨人','阪神タイガース':'阪神','横浜DeNAベイスターズ':'DeNA','広島東洋カープ':'広島','東京ヤクルトスワローズ':'ヤクルト','中日ドラゴンズ':'中日','福岡ソフトバンクホークス':'ソフトバンク','北海道日本ハムファイターズ':'日本ハム','千葉ロッテマリーンズ':'ロッテ','オリックス・バファローズ':'オリックス','埼玉西武ライオンズ':'西武','東北楽天ゴールデンイーグルス':'楽天'}
def parse(page):
    picks = []
    clean = lambda s: unescape(re.sub('<[^>]+>', '', s)).strip()
    for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>', page, re.S):
        cells = [clean(v) for v in re.findall(r'<t[hd]\b[^>]*>(.*?)</t[hd]>', row, re.S)]
        if len(cells) == 4 and cells[0] in TEAMS and cells[3] in TEAMS:
            picks.append(dict(team=TEAMS[cells[0]],name=cells[1],position=cells[2],from_team=TEAMS[cells[3]],rank='1',type='現役',**{'from':TEAMS[cells[3]]}))
    if len(picks) < 12 or len({p['team'] for p in picks}) != 12:
        raise ValueError('Incomplete result page')
    return picks
if __name__ == '__main__':
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument('--through',type=int,required=True,help='Last completed draft year')
    args=parser.parse_args()
    years={}
    for year in range(2022,args.through+1):
        url=f'https://npb.jp/geneki_draft/{year}/'
        page=subprocess.check_output(['curl','-fsSL',url]).decode('utf-8')
        years[str(year)]={'source':url,'picks':parse(page)}
    target=Path(__file__).parent/'assets/data/active_draft_history.json'
    target.write_text(json.dumps({'years':years},ensure_ascii=False,indent=2)+'\n')
    print({year:len(data['picks']) for year,data in years.items()})
