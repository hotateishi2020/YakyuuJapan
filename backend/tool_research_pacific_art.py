"""Fill missing biographies from current club profiles, with birth-date matching."""
import concurrent.futures
import fcntl
import json
import re
import urllib.parse
from tool_prepare_npb_player_art import OUT, soup, fetch

DOMAINS = {7: "softbankhawks.co.jp", 8: "seibulions.jp", 9: "fighters.co.jp",
           10: "buffaloes.co.jp", 11: "rakuteneagles.jp", 12: "marines.co.jp"}
directories = {}
for tid, domain in DOMAINS.items():
    url = f"https://www.{domain}/team/player/list/"
    doc = soup(url, f"club-{tid}-list.html")
    players = {}
    for a in doc.select("a.c-player-directory__link"):
        number = a.select_one(".c-player-directory__number")
        if number:
            players[number.get_text(strip=True)] = urllib.parse.urljoin(url, a["href"])
    directories[tid] = players
    print(json.dumps({"team": tid, "club_profiles": len(players)}), flush=True)


def work(path):
    r = json.loads(path.read_text())
    if r.get("status") not in ("needs_research", "needs_roster_verification"):
        return
    p = r["profile"]
    url = directories.get(p["id_team"], {}).get(p["uniform_number"])
    if not url:
        return
    try:
        sid = r["source_player_id"]
        doc = soup(url, f"{sid}-club.html")
        for el in doc.select("script,style,header,footer,nav"):
            el.decompose()
        text = doc.get_text(" ", strip=True)
        start, end = text.find("登録名/本名"), text.find("他の選手を見る")
        if start < 0:
            raise ValueError("Club profile section missing")
        text = text[start:end if end > start else None][:16000]
        y, m, d = map(int, p["date_birth"].split("-"))
        birthday = re.search(r"生年月日\s+(\d+)年(\d+)月(\d+)日", text)
        if not birthday or tuple(map(int, birthday.groups())) != (y, m, d):
            raise ValueError("Club birth date mismatch")
        birth = re.search(r"出身地\s+(.+?)\s+投打", text)
        if not birth:
            raise ValueError("Birthplace missing")
        r["profile"]["birth_place"] = birth[1]
        r["research"]["club_profile"] = text
        r["research"]["sources"].append(url)
        r["current_roster_verified"] = True
        r["prompt"] += (
            "\n追加の球団公式本人プロフィール（生年月日照合済み）:\n" + text +
            "\n背景は資料にある本人の出身地域。市町村が不明なら確認済み地域の一般的な自然景観にし、"
            "名所は追加しない。本人の出身校・プレースタイル・特技等から選ぶ。資料にない逸話は創作しない。"
        )
        r["status"] = "prepared"
        r["research_issues"] = []
        with (OUT / ".batch.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if json.loads(path.read_text()).get("status") not in ("needs_research", "needs_roster_verification"):
                return
            path.write_text(json.dumps(r, ensure_ascii=False, indent=2))
        return {"resolved_club": p["name_full"]}
    except Exception as e:
        return {"name": p["name_full"], "issue": str(e)}


jobs = [p for p in OUT.glob("[0-9]*.json") if not p.name.endswith(".error.json")]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for result in pool.map(work, jobs):
        if result:
            print(json.dumps(result, ensure_ascii=False), flush=True)
