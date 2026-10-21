"""Import public high-school results. Never uses registration keys/restricted pre-1978 qualifiers."""
import concurrent.futures
import html
import json
import re
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

BASE='https://www.hsbbdb.com/db/'
SOURCE=BASE+'hsbbdb.html'
OUT=Path(__file__).resolve().parent/'assets/data/high_school_records.json'
CACHE=Path('/tmp/koko-high-school-records')
BLOCKS={1:'北海道',2:'東北',3:'関東',4:'東京',5:'北信越',6:'東海',7:'近畿',8:'中国',9:'四国',10:'九州'}

def fetch(season, prefecture='-', end=2026):
    CACHE.mkdir(exist_ok=True)
    target=CACHE/f'{season}-{prefecture}-{end}.json'
    if target.exists(): return json.loads(target.read_text())
    params=dict(season=season,tiiki='-',tiku1=prefecture,tiku2='-',seq1=0,seq2=0,sno1=0,sno2=0,kai1='',kai2='',nen1=1978 if season==0 else 1915,nen2=end,hani=3,seiseki=0,keitai=0,kachi=0,gyakuten=0,tensa=0,ten='',inn=0,innkai='',innten='',koumei='',icchi=0,test='')
    url=BASE+('getYosen.php' if season==0 else 'getSiai.php')
    request=urllib.request.Request(url,data=urllib.parse.urlencode(params).encode())
    data=json.loads(urllib.request.urlopen(request,timeout=55).read())
    if not isinstance(data,list) or (data and 'kaisen_nm' not in data[0]): raise ValueError(f'Unexpected response {season}/{prefecture}')
    target.write_text(json.dumps(data,ensure_ascii=False))
    return data

def placements(games):
    # Follow each finalist's earlier wins to get disjoint 1/2/4/8/16 finishes.
    ordered=sorted(games,key=lambda g:int(g.get('game_no') or 0))
    finals=[(i,g) for i,g in enumerate(ordered) if re.sub(r'\s','',g['kaisen_nm'])=='決勝']
    if not finals:return None
    end,final=finals[-1]
    if not final.get('wkoumei') or not final.get('lkoumei'):return None
    places={'1':[final['wkoumei']],'2':[final['lkoumei']],'4':[],'8':[],'16':[]}
    frontier=[(final['wkoumei'],end),(final['lkoumei'],end)]
    for rank in ['4','8','16']:
        next_round=[]
        for team,before in frontier:
            wins=[(i,g) for i,g in enumerate(ordered[:before]) if g['wkoumei']==team and g['lkoumei']!=team and re.sub(r'\s','',g['kaisen_nm']) not in ['3位決定戦','３位決定戦','順位決定戦']]
            if not wins:continue
            i,g=wins[-1]
            if g['lkoumei'] not in sum(places.values(),[]): places[rank].append(g['lkoumei'])
            next_round.extend([(team,i),(g['lkoumei'],i)])
        frontier=next_round
    return places

def tournaments(games, season, pref_names):
    groups=defaultdict(list)
    for g in games:
        year=int(g['nen'])
        region=g.get('tikuwari_no') if season in [4,5] else ((g.get('tikuwari_no') or g.get('tiku_no')) if season==0 else g.get('tiku_no2'))
        if season in [1,2]:region=0
        groups[(year,str(region),str(g.get('tw_seq_no') or 0))].append(g)
    result=[]
    for (year,region,seq),items in groups.items():
        places=placements(items)
        if not places:continue
        scope='national' if season in [1,2] else 'block' if season in [4,5] else 'district'
        region_number=int(region) if region.isdigit() else 0
        label=BLOCKS.get(region_number, f'旧地区{region}') if scope=='block' else pref_names.get(str(region_number),items[-1].get('tiku_nm') or f'地区{region}')
        if scope=='national':label='全国'
        period='春' if season in [1,5,9] else '夏' if season in [0,2] else '秋'
        result.append(dict(year=year,scope=scope,region=label,season=period,division=seq,places=places,source=SOURCE,
            district_name=next((g.get('tiku_nm') for g in reversed(items) if g.get('tiku_nm')), label),
            champion_pref=pref_names.get(str(next(g for g in reversed(items) if re.sub(r'\s','',g['kaisen_nm'])=='決勝').get('win_no')),'')))
    return result

def main():
    names_response=urllib.request.urlopen(urllib.request.Request(BASE+'getTiku.php',data=b'season=1'),timeout=30)
    names={r['tiku_no'].split(':')[0]:r['tiku_nm'] for r in json.loads(names_response.read()) if r['tiku_no']!='-'}
    jobs=[(s,'-') for s in [1,2,4,5,8,9]]+[(0,i) for i in range(1,48)]
    records=[];errors=[]
    def work(job):
        s,p=job
        data=fetch(s,p)
        return tournaments(data,s,names)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures={pool.submit(work,j):j for j in jobs}
        for future in concurrent.futures.as_completed(futures):
            job=futures[future]
            try: rows=future.result(); records.extend(rows);print(job,len(rows),flush=True)
            except Exception as e: errors.append([job,str(e)]);print('ERROR',job,str(e),flush=True)
    url='https://data-man.com/kokoyakyu/ranking/individual/'
    page=urllib.request.urlopen(url,timeout=30).read().decode()
    hrs=[]
    for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>',page,re.S):
        if 'class="homerun ' not in tr:continue
        cells=[html.unescape(re.sub('<[^>]*>','',c)).strip() for c in re.findall(r'<t[dh]\b[^>]*>(.*?)</t[dh]>',tr,re.S)]
        if len(cells)==5 and cells[4].isdigit():hrs.append(dict(name=cells[1],school=cells[2],prefecture=cells[3],value=int(cells[4]),source=url))
    # Remove overlap from prefecture filters returning the same final.
    unique={(r['scope'],r['year'],r['season'],r['region'],r['division'],r['places']['1'][0]):r for r in records}
    OUT.write_text(json.dumps(dict(tournaments=sorted(unique.values(),key=lambda r:(-r['year'],r['scope'],r['season'],r['region'])),home_runs=hrs,reported_home_runs=json.loads((OUT.parent/'high_school_reported_home_runs.json').read_text()),through_year=2026,coverage='春夏の全国大会、春秋のブロック大会、春秋の都道府県大会（主に8強まで）、1978年以降の夏の地方大会。出典の未収録結果は含みません。',errors=errors),ensure_ascii=False,separators=(',',':'))+'\n')
    print('Saved',len(unique),'tournaments;',len(hrs),'home run records;',len(errors),'errors',flush=True)

if __name__=='__main__':main()
