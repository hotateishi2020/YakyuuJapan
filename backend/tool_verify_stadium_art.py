"""Validate generated stadium assets; contact sheets are QA-only, not app assets."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib
import json

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'backend/data/stadium-image-refresh-v2.json').read_text())
missing=[];invalid=[];seen={};found=[]
for row in manifest:
    p=root/row['path']
    if not p.exists():missing.append(row['path']);continue
    try:
        with Image.open(p) as im:
            im.load()
            if min(im.size)<128:invalid.append(f'{p.name}: too small')
            if row['view']=='outside' and (im.mode!='RGBA' or im.getchannel('A').getextrema()[0]!=0):
                invalid.append(f'{p.name}: exterior lacks transparency')
        digest=hashlib.sha256(p.read_bytes()).hexdigest()
        if digest in seen:invalid.append(f'{row["path"]}: duplicates {seen[digest]}')
        seen[digest]=row['path'];found.append(row)
    except Exception as e:invalid.append(f'{p.name}: {e}')
output=Path('/tmp/koko-stadium-review');output.mkdir(exist_ok=True)
for view in ['inside','outside']:
    rows=[r for r in found if r['view']==view]
    for start in range(0,len(rows),24):
        batch=rows[start:start+24]
        sheet=Image.new('RGB',(960,220*((len(batch)+3)//4)),(225,229,235));draw=ImageDraw.Draw(sheet)
        for i,r in enumerate(batch):
            im=Image.open(root/r['path']).convert('RGBA');im.thumbnail((232,192))
            x=(i%4)*240+(240-im.width)//2;y=(i//4)*220
            sheet.paste(im,(x,y),im)
            draw.text(((i%4)*240+4,y+194),Path(r['path']).stem.replace('-generated-v2',''),fill='black')
        sheet.save(output/f'{view}-{start//24}.jpg')
print(json.dumps({'expected':len(manifest),'saved':len(found),'missing':len(missing),'invalid':invalid,'review':str(output)},ensure_ascii=False))
raise SystemExit(1 if missing or invalid else 0)
