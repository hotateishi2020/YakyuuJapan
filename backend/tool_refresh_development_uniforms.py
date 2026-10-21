"""Import NPB annual developmental registration lists, preserving leading zeroes.
Public HTML only; updates the local catalog atomically, without DB writes.
"""
import concurrent.futures, datetime, html, json, pathlib, re, time, urllib.request, urllib.error
ROOT = pathlib.Path(__file__).resolve().parent
CACHE = pathlib.Path('/tmp/koko-development-uniforms'); CACHE.mkdir(exist_ok=True)
TEAMS = dict(g='読売ジャイアンツ',t='阪神タイガース',db='横浜DeNAベイスターズ',s='東京ヤクルトスワローズ',d='中日ドラゴンズ',c='広島東洋カープ',h='福岡ソフトバンクホークス',f='北海道日本ハムファイターズ',m='千葉ロッテマリーンズ',e='東北楽天ゴールデンイーグルス',l='埼玉西武ライオンズ',b='オリックス・バファローズ')
def clean(s): return html.unescape(re.sub('<[^>]+>','',s)).strip()
def read(item):
 year,code=item; url=f'https://npb.jp/announcement/{year}/registereddev_{code}.html'; path=CACHE/f'{year}-{code}.html'
 try:
  if not path.exists():
   body=urllib.request.urlopen(url,timeout=30).read().decode();path.write_text(body);time.sleep(.15)
  body=path.read_text()
 except urllib.error.HTTPError as e:
  if e.code==404:return [],url
  raise
 rows=[]
 for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>',body,re.S):
  cells=re.findall(r'<td\b[^>]*>(.*?)</td>',tr,re.S)
  if len(cells)<3:continue
  number=clean(cells[1]);name=clean(cells[2]);player=re.search(r'/players/(\d+)\.html',cells[2])
  if not re.fullmatch(r'\d{3}',number) or not player:continue
  rows.append(dict(player_key='npb:'+player[1],name=name,number=number,team=TEAMS[code],first_year=year,last_year=year,registration='育成',source=url))
 return rows,None
if __name__=='__main__':
 year=datetime.date.today().year
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: results=list(pool.map(read,[(y,c) for y in range(2006,year+1) for c in TEAMS]))
 rows=[r for result,_ in results for r in result]; missing=[url for _,url in results if url]
 assert len(rows)>100
 p=ROOT/'data/baseball-catalog.json';data=json.loads(p.read_text())
 data['uniforms']=[r for r in data['uniforms'] if r.get('registration')!='育成']+rows
 data['development_uniforms_checked_at']=datetime.date.today().isoformat();data['development_uniforms_unavailable_sources']=missing
 tmp=p.with_suffix('.tmp');tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');tmp.replace(p)
 print('Developmental uniform tenures:',len(rows),'Unavailable annual pages:',len(missing))
