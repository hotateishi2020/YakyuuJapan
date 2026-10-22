"""Import actual appearances from WBSC final reports. Requires pypdf.
Run after refresh_mlb_country_profiles.py; cache reports in tmp/pdfs.
Identity links require matching birth date AND family name; no fuzzy names.
"""
import datetime
import json
from pathlib import Path
import re
import unicodedata
import urllib.request
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[2]
SOURCES={
 2015:'https://static.wbsc.org/uploads/federations/0/documents/20170630124244-2015%20Premier12%20Final%20Report.pdf',
 2019:'https://s3-eu-west-1.amazonaws.com/static.wbsc.org/upload/a4210fb4-3a35-d489-70cd-a54731d5ca78.pdf',
 2024:'https://static.wbsc.org/uploads/federations/0/documents/82f90f98-607b-6a2c-59ba-47dbefdf741f.pdf'}
CODES={'AUS':'AU','CAN':'CA','CUB':'CU','DOM':'DO','ITA':'IT','JPN':'JP','KOR':'KR',
       'MEX':'MX','NED':'NL','PAN':'PA','PUR':'PR','TPE':'TW','USA':'US','VEN':'VE'}
def normalize(s):
 return re.sub('[^a-z]','',unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode().lower())

def import_report(year,path,profiles):
 pages=[p.extract_text(extraction_mode='layout') for p in PdfReader(path).pages]
 roster={}; appeared=set()
 for page_number,text in enumerate(pages,1):
  header=re.search(r'^\s*[A-Z][A-Z ]+\s{3,}('+'|'.join(CODES)+r')\s*$',text,re.M)
  if not header:continue
  code=CODES[header[1]]
  if 'ROSTER' in text:
   for line in text.splitlines():
    m=re.match(r'\s*(\d+)\s+(.+?)\s+(\d{4}-\d\d-\d\d|\d\d[-/]\d\d[-/]\d{4})(?:\s|$)',line)
    if not m:continue
    raw_date=m[3]
    birth=raw_date if raw_date[4]=='-' else datetime.datetime.strptime(raw_date.replace('/','-'),'%d-%m-%Y').date().isoformat()
    label=re.split(r'\s{2,}(?:P|C|IF|OF|UTL|DH|SS|1B|2B|3B)\b',m[2])[0].strip()
    hits=[p for p in profiles if p['birth_date']==birth and p['last_name'] and normalize(p['last_name']) in normalize(label)]
    roster[(code,int(m[1]))]={'name':label,'birth_date':birth,'country_code':code,
      'source_player_id':hits[0]['source_player_id'] if len(hits)==1 else None,
      'year':year,'tournament':'Premier12','source':SOURCES[year]}
  elif re.search(r'Sorted by Batting',text,re.I):
   section = 'batting'
   for line in text.splitlines():
    if re.search('Sorted by Earned',line,re.I):section='pitching'
    if re.search('Sorted by Fielding',line,re.I):section='fielding'
    m=re.match(r'\s*(\d+)\s+.+?\s+(?:\d*\.\d+|---)\s+(\d+)-(\d+)\s+(.*)',line)
    if not m or section=='fielding':continue
    values=m[4].split()
    games=int(m[2]) if section=='batting' else int(values[0 if year==2015 else 2])
    if games>0:appeared.add((code,int(m[1])))

 rows=[dict(roster[k]) for k in sorted(appeared) if k in roster]
 print(year,'roster',len(roster),'appeared',len(rows),'ID matched',sum(bool(r['source_player_id']) for r in rows))
 return rows

if __name__=='__main__':
 profiles=json.loads((ROOT/'backend/data/mlb_country_profiles.json').read_text())['players']
 rows=[]
 for year,url in SOURCES.items():
  path=ROOT/f'tmp/pdfs/premier12-{year}.pdf';path.parent.mkdir(parents=True,exist_ok=True)
  if not path.exists():urllib.request.urlretrieve(url,path)
  rows.extend(import_report(year,path,profiles))
 (ROOT/'backend/data/premier12_appearances.json').write_text(json.dumps({'checked_at':datetime.date.today().isoformat(),'appearances':rows},ensure_ascii=False,indent=2)+'\n')
