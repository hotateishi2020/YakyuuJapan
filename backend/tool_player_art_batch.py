"""Local durable handoff for built-in image generation; never marks art reviewed."""
import fcntl
import json
import pathlib
import re
import shutil
import sys
from npb_art_roster import departure

BASE = pathlib.Path(__file__).resolve().parent / "data/player-art-npb-v3"


def save(path, record):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(record, ensure_ascii=False, indent=2))
    tmp.replace(path)


def records():
    for path in BASE.glob("[0-9]*.json"):
        if path.name.endswith(".error.json"):
            continue
        yield path, json.loads(path.read_text())


action = sys.argv[1]
if action == "claim":
    if (BASE / "PAUSE").exists():
        print("null")
        sys.exit(0)
    with (BASE / ".batch.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        all_records = list(records())
        moves = json.loads((BASE.parent / "roster-moves-2026.json").read_text())
        for path, r in all_records:
            retired = departure(r, moves)
            if retired and r["status"] not in ("registered", "generating"):
                r.update(status="excluded", reviewed=False,
                         reason=retired.get("departure_reason", "退団"),
                         exclusion_source=retired.get("status_source"))
                save(path, r)
            notes = " ".join(r.get("research", {}).get("roster_row", [])[7:])
            if r["status"] in ("prepared", "needs_research") and (
                    any(word in notes for word in ["自由契約", "任意引退", "退団"]) or
                    r["source_player_id"] == "51755115"):
                r["status"] = "excluded"
                r["reason"] = "公式の退団・引退情報に基づき現役所属選手の対象から除外"
                save(path, r)
            if r["status"] == "prepared" and not r.get("current_roster_verified"):
                bio = r.get("research", {}).get("wikipedia_profile", "").split("基本情報")[0]
                club = r["profile"]["name_team"]
                match = re.search(r"#\s*(\d+)", bio)
                agrees = (club in bio or (club == "巨人" and "ジャイアンツ" in bio))
                if not match or not agrees or match[1] != r["profile"]["uniform_number"]:
                    r["status"] = "needs_roster_verification"
                    r["reason"] = "NPBシーズン名簿と経歴資料の現在所属・背番号を球団公式で追加照合"
                    save(path, r)
        counts = {}
        for _, r in all_records:
            if r["status"] in ("generating", "generated", "reviewed", "registered"):
                tid = r["profile"]["id_team"]
                counts[tid] = counts.get(tid, 0) + 1
        ready = [(p, r) for p, r in all_records if r["status"] == "prepared"]
        ready.sort(key=lambda pr: (counts.get(pr[1]["profile"]["id_team"], 0),
                                  len(pr[1]["research"]["wikipedia_notes"]) * -1))
        if not ready:
            print("null")
        else:
            path, r = ready[0]
            bio = r["research"]["wikipedia_profile"]
            m = re.search(r"出身地\s+(.+?)\s+生年月日", bio)
            birthplace = m[1] if m else r["profile"].get("birth_place", "")
            # The exact birthplace overrides stadium locations/career references.
            r["prompt"] += (
                "\n\n今回の厳守事項: 本人1人だけを全身で描く。"
                f"背景の出身地は【{birthplace}】。本拠地球場や所属球団の都市を"
                "出身地の代わりに使わない。本文中の写真撮影場所を出身地と混同しない。"
                "有名な建造物の所在地が確実でなければ、この出身地の一般的な風景にする。"
                "建物看板を含め地名は一切書かない。帽子・ヘルメットを着用しない。"
                "既存アニメ漫画キャラ、無意味な犬猫、趣味の推測は禁止。"
                "表情は目眉だけ。補助の日本語文字は2個まで。"
                "髪型は本人らしく、参照イラストの髪型をそのまま転用しない。"
            )
            r["prompt"] += (
                "\n品質確認後の重要な追加制約: 背景は出身市町村の一般的な自然・住宅・街路の風景にする。"
                "資料に明記されていない有名な塔・寺社・城・鳥居・銅像・橋・球場を推測で追加しない。"
                "風景の代わりに別の市町村の有名観光地を入れてはいけない。"
                "受賞歴は下記の本人の表彰・タイトル一覧だけから選ぶ。本文の他選手の受賞や候補歴と混同しない。"
                "一覧が空なら賞名・トロフィー・金のグラブ・メダルを一切描かず、出身校や特技・プレースタイルを題材にする。"
                "ベストナイン等を金のグラブで表現しない。新人特別賞を新人王と書かない。"
                "\n本人の表彰・タイトル一覧: " + r["research"].get("confirmed_awards_section", "") +
                "\n投打は次の公式プロフィールに厳密に合わせる。左投手のボールは本人の左手、グラブは右手。"
                "右投手は逆。体に対する左右を正しく描く。\n" + r["research"]["official_profile"][:600]
            )
            r["status"] = "generating"
            save(path, r)
            print(json.dumps({"path": str(path), "prompt": r["prompt"],
                              "references": [r["style_reference"], r["reference_path"]],
                              "name": r["profile"]["name_full"]}, ensure_ascii=False))
elif action == "complete":
    path = pathlib.Path(sys.argv[2])
    r = json.loads(path.read_text())
    generated = pathlib.Path(sys.argv[3])
    shutil.copyfile(generated, r["image_path"])
    r["status"] = "generated"
    r["generation_method"] = "built-in image_gen"
    r["reviewed"] = False
    retired = departure(r, json.loads((BASE.parent / "roster-moves-2026.json").read_text()))
    if retired:
        r.update(status="excluded", reason=retired.get("departure_reason", "退団"),
                 exclusion_source=retired.get("status_source"))
    save(path, r)
    print(json.dumps({"saved": r["image_path"], "name": r["profile"]["name_full"]},
                     ensure_ascii=False))
elif action == "fail":
    path = pathlib.Path(sys.argv[2])
    r = json.loads(path.read_text())
    r["status"] = "generation_failed"
    r["generation_error"] = sys.argv[3]
    save(path, r)
elif action == "status":
    counts = {}
    for _, r in records():
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print(json.dumps(counts))
else:
    raise ValueError("Use claim | complete | fail | status")
