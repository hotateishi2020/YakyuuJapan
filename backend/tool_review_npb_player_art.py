"""Build contact sheets for manual review, or record an explicit review decision."""
import json
import pathlib
import sys
from PIL import Image, ImageDraw

BASE = pathlib.Path(__file__).resolve().parent / "data/player-art-npb-v3"

if len(sys.argv) > 2 and sys.argv[1] in ("approve", "fix"):
    action, note, *ids = sys.argv[1:]
    for sid in ids:
        path = BASE / f"{sid}.json"
        r = json.loads(path.read_text())
        if not pathlib.Path(r["image_path"]).is_file():
            raise ValueError(f"Missing image: {sid}")
        r.update(reviewed=action == "approve",
                 status="reviewed" if action == "approve" else "needs_visual_fix",
                 review_notes=note)
        path.write_text(json.dumps(r, ensure_ascii=False, indent=2))
else:
    records = []
    for p in sorted(BASE.glob("[0-9]*.json")):
        if p.name.endswith(".error.json"):
            continue
        r = json.loads(p.read_text())
        if r.get("status") == "generated":
            records.append(r)
    out = pathlib.Path("/tmp/koko-npb-art-review")
    out.mkdir(exist_ok=True)
    for i in range(0, len(records), 4):
        group = records[i:i + 4]
        page = Image.new("RGB", (1024, 1568), "white")
        draw = ImageDraw.Draw(page)
        for n, r in enumerate(group):
            with Image.open(r["image_path"]) as im:
                im.thumbnail((512, 752))
                x, y = n % 2 * 512, n // 2 * 784
                page.paste(im, (x, y))
                draw.text((x + 5, y + 754), r["source_player_id"], fill="black")
        path = out / f"page-{i // 4}.jpg"
        page.save(path)
        print(json.dumps({"sheet": str(path), "players": [
            {"id": r["source_player_id"], "name": r["profile"]["name_full"],
             "bio": r["research"]["wikipedia_profile"].split("経歴")[0],
             "official": r["research"]["official_profile"][:500]} for r in group
        ]}, ensure_ascii=False))
manifest = [str(p) for p in sorted(BASE.glob("[0-9]*.json"))
            if not p.name.endswith(".error.json") and json.loads(p.read_text()).get("reviewed")]
(BASE / "reviewed-manifest.json").write_text(json.dumps(manifest, indent=2))
