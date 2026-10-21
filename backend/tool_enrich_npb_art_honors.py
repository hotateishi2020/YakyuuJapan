import json
import fcntl
from tool_prepare_npb_player_art import OUT, soup
from bs4 import BeautifulSoup

for path in OUT.glob("[0-9]*.json"):
    if path.name.endswith(".error.json"):
        continue
    r = json.loads(path.read_text())
    if r.get("status") not in ("prepared", "needs_roster_verification"):
        continue
    research = r["research"]
    sid = r["source_player_id"]
    for cached in (OUT / "sources").glob(f"{sid}-wiki*.html"):
        doc = BeautifulSoup(cached.read_bytes(), "html.parser")
        box = doc.select_one("table.infobox")
        if not box or box.get_text(" ", strip=True) != research["wikipedia_profile"]:
            continue
        awards = []
        for section in doc.select("section"):
            h = section.find(["h2", "h3"])
            if h and h.get_text(strip=True) in ("表彰", "タイトル"):
                awards.append(section.get_text(" ", strip=True))
        research["confirmed_awards_section"] = "\n".join(awards)[:4000]
        break
    with (OUT / ".batch.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = json.loads(path.read_text())
        if current.get("status") in ("prepared", "needs_roster_verification"):
            current["research"]["confirmed_awards_section"] = research.get("confirmed_awards_section", "")
            path.write_text(json.dumps(current, ensure_ascii=False, indent=2))
