"""Resolve alternate article names while requiring the same official birth date."""
import concurrent.futures
import json
import pathlib
import re
import fcntl
import urllib.parse
from tool_prepare_npb_player_art import OUT, soup, norm


def work(path):
    r = json.loads(path.read_text())
    if r.get("status") != "needs_research":
        return
    sid = r["source_player_id"]
    name = norm(r["profile"]["name_full"])
    if "（" in name:
        name = name.split("（", 1)[1].rstrip("）")
    candidates = [name, name + "_(野球)", name + "_(野球選手)"]
    urls = ["https://ja.wikipedia.org/wiki/" + urllib.parse.quote(t) for t in candidates]
    eng = r["research"]["english_name"].title().replace(" ", "_")
    if re.search(r"[Ａ-ＺA-Z]．|[ァ-ヶ]{3}", name):
        for title in [eng, eng + "_(baseball)"]:
            try:
                e = soup("https://en.wikipedia.org/wiki/" + title, f"{sid}-enwiki-{len(title)}.html")
                for a in e.select('a[href*="ja.wikipedia.org/wiki/"]'):
                    urls.insert(0, a["href"])
                if any("ja.wikipedia.org" in u for u in urls[:1]):
                    break
            except Exception:
                pass
    y, m, d = map(int, r["profile"]["date_birth"].split("-"))
    for i, url in enumerate(dict.fromkeys(urls)):
        try:
            wiki = soup(url, f"{sid}-wiki-alternate-{i}.html")
            box = wiki.select_one("table.infobox")
            if not box:
                continue
            bio = box.get_text(" ", strip=True)
            if f"{y}年{m}月{d}日" not in bio and f"{y}-{m:02d}-{d:02d}" not in bio:
                continue
            chunks = []
            for section in wiki.select("section"):
                h = section.find(["h2", "h3"])
                if h and any(x in h.get_text() for x in ["人物", "特徴", "プレースタイル", "プロ入り前", "経歴"]):
                    chunks += [p.get_text(" ", strip=True) for p in section.find_all("p")]
            notes = "\n".join(dict.fromkeys(chunks))[:22000]
            if not notes:
                continue
            old = json.dumps(r["research"], ensure_ascii=False)
            r["research"].update(wikipedia_profile=bio, wikipedia_notes=notes)
            r["research"]["sources"].append(url)
            r["prompt"] = r["prompt"].replace(old, json.dumps(r["research"], ensure_ascii=False))
            r["status"] = "prepared"
            r["research_issues"] = []
            with (OUT / ".batch.lock").open("w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                if json.loads(path.read_text()).get("status") != "needs_research":
                    return
                path.write_text(json.dumps(r, ensure_ascii=False, indent=2))
            return {"resolved": r["profile"]["name_full"]}
        except Exception:
            continue
    return {"unresolved": r["profile"]["name_full"]}


if __name__ == "__main__":
    jobs = [p for p in OUT.glob("[0-9]*.json") if not p.name.endswith(".error.json")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(work, jobs):
            if result:
                print(json.dumps(result, ensure_ascii=False), flush=True)
