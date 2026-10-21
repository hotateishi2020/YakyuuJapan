"""Import archived starting lineups; never replace live team-strength snapshots.
Source: sta-men.jp, whose index lists the available team/seasons.
"""
import collections
import concurrent.futures
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parent
CACHE = Path('/tmp/koko-regular-history')
CLUBS = {'giants':'巨人','tigers':'阪神','dragons':'中日','whales':'DeNA','baystars':'DeNA',
         'carp':'広島','swallows':'ヤクルト','hawks':'ソフトバンク','lions':'西武',
         'fighters':'日本ハム','marines':'ロッテ','orions':'ロッテ','eagles':'楽天',
         'braves':'オリックス','bluewave':'オリックス','buffaloes':'オリックス','buffaloes2':'近鉄'}
POSITIONS = {'1':'P','P':'P','2':'C','3':'1B','4':'2B','5':'3B','6':'SS','7':'LF','8':'CF','9':'RF','D':'DH'}
LABELS = {'P':'投手','C':'捕手','1B':'一塁','2B':'二塁','3B':'三塁','SS':'遊撃','LF':'左翼','CF':'中堅','RF':'右翼','DH':'指名打者'}
class Rows(HTMLParser):
    def __init__(self):
        super().__init__(); self.rows=[]; self.row=[]; self.cell=None; self.decoy=False
    def handle_starttag(self,tag,attrs):
        if tag=='tr': self.row=[]
        if tag in ('td','th'): self.cell=''
        if tag=='span' and 'tei' in dict(attrs).get('class','').split(): self.decoy=True
    def handle_data(self,data):
        if self.cell is not None and not self.decoy: self.cell+=data
    def handle_endtag(self,tag):
        if tag=='span': self.decoy=False
        if tag in ('td','th') and self.cell is not None:
            self.row.append(re.sub(r'\s+','',self.cell)); self.cell=None
        if tag=='tr': self.rows.append(self.row); self.row=[]

def fetch(path):
    CACHE.mkdir(parents=True,exist_ok=True)
    cache=CACHE/path
    if cache.exists(): return cache.read_text()
    with urllib.request.urlopen('https://sta-men.jp/'+path, timeout=30) as response:
        body=response.read().decode('cp932',errors='replace')
    cache.write_text(body); return body

def parse(body,year,club,source):
    parser=Rows(); parser.feed(body)
    order=collections.defaultdict(collections.Counter); positions=collections.defaultdict(collections.Counter)
    seen=set(); games=0
    for row in parser.rows:
        if games and len(row)<10 and re.search('日本シリーズ|クライマックス|プレーオフ|アジアシリーズ|日韓クラブ', ''.join(row)): break
        if len(row)<10 or not re.match(rf'^{year}/\d{{1,2}}/\d{{1,2}}',row[0]): continue
        names=[re.fullmatch(r'([1-9DP])(.+)',cell) for cell in row[1:10]]
        if not all(names) or tuple(row[:11]) in seen: continue
        seen.add(tuple(row[:11])); games+=1
        for index,match in enumerate(names,1):
            pos,name=match.groups(); order[index][name]+=1; positions[POSITIONS[pos]][name]+=1
        if not any(m[1] in ('1','P') for m in names) and len(row)>10 and row[10].startswith('P'):
            positions['P'][row[10][1:]]+=1
    if games<50: raise ValueError(f'incomplete season: {games} games')
    def groups(values,labels):
        return [{'slot':slot,'label':label,'total':games,'players':[
            {'name':name,'count':count,'rate':round(count*100/games,1)}
            for name,count in sorted(values.get(slot,{}).items(),key=lambda v:(-v[1],v[0]))]}
            for slot,label in labels.items()]
    return {'year':year,'org':'npb','club_name':club,'game_count':games,'lineup_game_count':games,
            'positions':groups(positions,LABELS),'batting_order':groups(order,{i:f'{i}番' for i in range(1,10)}),
            'source_url':source,'source_label':'スタメンデータベース',
            'notes':['試合別スタメンを集計。ポストシーズンを除外。途中出場・投手の左右別起用はこの資料では未取得。氏名は出典の表記。']}

def main():
    index=fetch('index.html')
    links=sorted(set(re.findall(r'href="(\d{4}[a-z0-9]+\.html)"',index)))
    jobs=[]
    for link in links:
        year=int(link[:4]); code=link[4:-5]
        if year>2025: continue
        club=CLUBS.get(code)
        if code=='buffaloes' and year<2005: club='近鉄'
        if club is None: raise ValueError(f'Unknown club: {link}')
        jobs.append((link,year,club))
    path=ROOT/'data/regular-history.json'
    existing=json.loads(path.read_text()) if path.exists() else {'rows':[]}
    result={(r['year'],r['club_name']):r for r in existing['rows']}; errors=[]
    def run(job):
        link,year,club=job
        return parse(fetch(link),year,club,'https://sta-men.jp/'+link)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures={pool.submit(run,j):j for j in jobs}
        for future in concurrent.futures.as_completed(futures):
            try:
                row=future.result()
                key=(row['year'],row['club_name'])
                prior=result.get(key,{})
                row={**prior,**row}
                if row.get('official_stat_sources'):
                    from tool_enrich_regular_history import normalize_groups
                    normalize_groups(row)
                result[key]=row
            except Exception as e: errors.append(f'{futures[future][0]}: {e}')
    rows=sorted(result.values(),key=lambda r:(-r['year'],r['club_name']))
    temp=path.with_suffix('.tmp');temp.write_text(json.dumps({'rows':rows,'errors':errors},ensure_ascii=False));temp.replace(path)
    print(json.dumps({'team_seasons':len(rows),'years':sorted(set(r['year'] for r in rows)),'errors':errors},ensure_ascii=False))
    if errors: raise SystemExit(1)
if __name__=='__main__': main()
