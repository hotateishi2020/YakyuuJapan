"""QA contact sheets only. Does not modify generated deliverables."""
import json,hashlib,sys
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'backend/data/player-art-initial-manifest.json').read_text())
rows=[];missing=[];invalid=[];hashes=set()
for meta in manifest:
 r=json.loads(Path(meta).read_text());p=Path(r['image_path'])
 if not p.exists():missing.append(r['source_player_id']);continue
 try:
  with Image.open(p) as im:
   im.load()
   if im.height<=im.width or min(im.size)<512:invalid.append(r['source_player_id']+': invalid dimensions')
  h=hashlib.sha256(p.read_bytes()).hexdigest()
  if h in hashes:invalid.append(r['source_player_id']+': duplicate')
  hashes.add(h);rows.append(r)
 except Exception as e:invalid.append(str(e))
out=Path('/tmp/koko-player-art-review');out.mkdir(exist_ok=True)
review_rows=[r for r in rows if not r.get('reviewed')] if '--unreviewed' in sys.argv else rows
for start in range(0,len(review_rows),8):
 group=review_rows[start:start+8];sheet=Image.new('RGB',(1200,490*((len(group)+3)//4)),(232,236,242));draw=ImageDraw.Draw(sheet)
 for i,r in enumerate(group):
  im=Image.open(r['image_path']).convert('RGB');im.thumbnail((296,450));x=(i%4)*300+(300-im.width)//2;y=(i//4)*490;sheet.paste(im,(x,y));draw.text(((i%4)*300+3,y+454),r['source_player_id']+'  #'+r['profile']['uniform_number'],fill='black');draw.text(((i%4)*300+3,y+470),r['research']['english_name'],fill='black')
 sheet.save(out/f'players-{start//8:02}.jpg')
print(json.dumps({'expected':len(manifest),'saved':len(rows),'missing':missing,'invalid':invalid,'review':str(out)}))
