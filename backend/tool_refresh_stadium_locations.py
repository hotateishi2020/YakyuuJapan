"""Enrich stadium locations and add current farm/regional venues from public NPB data."""
import concurrent.futures, json, pathlib, urllib.request, re
ROOT=pathlib.Path(__file__).resolve().parent

def get(url):
 return json.loads(urllib.request.urlopen(url,timeout=30).read())

def main():
 path=ROOT/'data/stadium-catalog.json'; data=json.loads(path.read_text());rows=data['stadiums']
 def enrich(row):
  row=dict(row)
  row.setdefault('stadium_level','first')
  source=row.get('source','')
  if 'npb.jp/stadium/json/' in source:
   info=get(source);row['address']=info.get('address');row['address_source']=source
  elif 'statsapi.mlb.com' in source:
   url=source.split('?')[0]+'?hydrate=location';info=get(url)['venues'][0].get('location',{})
   row['address']=', '.join(str(info[k]) for k in ['address1','city','state','postalCode','country'] if info.get(k));row['address_source']=url
  return row
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: rows=list(pool.map(enrich,[r for r in rows if r.get('stadium_level','first')=='first']))
 farms=[
 ('読売ジャイアンツ','ジャイアンツタウンスタジアム','東京都稲城市','20260123_01'),
 ('東京ヤクルトスワローズ','ヤクルト戸田球場','埼玉県戸田市','20260123_01'),
 ('北海道日本ハムファイターズ','ファイターズ鎌ケ谷スタジアム','千葉県鎌ケ谷市','20260220_02'),
 ('横浜DeNAベイスターズ','横須賀スタジアム','神奈川県横須賀市','20260220_02'),
 ('東北楽天ゴールデンイーグルス','森林どりスタジアム泉','宮城県仙台市泉区','20260220_02'),
 ('千葉ロッテマリーンズ','ロッテ浦和球場','埼玉県さいたま市南区','20260206_01'),
 ('埼玉西武ライオンズ','CAR3219フィールド','埼玉県所沢市','20260206_01'),
 ('福岡ソフトバンクホークス','タマホーム スタジアム筑後','福岡県筑後市','20260312_01'),
 ('オリックス・バファローズ','杉本商事バファローズスタジアム舞洲','大阪府大阪市此花区','20260312_01'),
 ('中日ドラゴンズ','ナゴヤ球場','愛知県名古屋市中川区','20260312_01'),
 ('阪神タイガース','日鉄鋼板SGLスタジアム尼崎','兵庫県尼崎市','20260306_01'),
 ('広島東洋カープ','広島東洋カープ由宇練習場','山口県岩国市','20260306_01'),
 ]
 for team,name,address,source in farms:
  rows.append(dict(org='npb',team=team,name=name,match=name,address=address,stadium_level='farm',category='屋外球場',source=f'https://npb.jp/news/detail/{source}.html'))
 primary_ids={re.search(r'/json/(\d+)',r.get('source',''))[1] for r in rows if '/json/' in r.get('source','')}
 for row in get('https://npb.jp/stadium/stadium_list.json'):
  if row['id'] in primary_ids or row['close']=='true' or row['title']=='ナゴヤ球場':continue
  rows.append(dict(org='npb',name=row['title'],match=row['title'],team='—',address=row['pref']+row['city'],stadium_level='regional',source='https://npb.jp/stadium/detail.html?'+row['id']))
 assert all(r.get('address') for r in rows)
 data['stadiums']=rows;tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');tmp.replace(path)
 print('Stadiums',len(rows),'first',sum(r['stadium_level']=='first' for r in rows),'farm',sum(r['stadium_level']=='farm' for r in rows))
if __name__=='__main__':main()
