"""Match dated, sourced roster departures without confusing same-name players."""
import datetime
import re
import unicodedata


def normalized(name):
    name = unicodedata.normalize("NFKC", name)
    name = re.sub(r"\s|・", "", name)
    name = re.sub(r"^[A-Z]\.", "", name)
    return name.replace("髙", "高").replace("﨑", "崎")


def departure(record, moves):
    p = record.get("profile", {})
    names = {normalized(p.get("name_full", "")), *map(normalized, p.get("names", []))}
    official = record.get("research", {}).get("official_profile", "")
    today = datetime.date.today().isoformat()
    matches = []
    for move in moves:
        if move.get("kind") not in ("arrival", "departure"):
            continue
        date = move.get("status_as_of", "")
        if not date or date > today or move.get("team") != p.get("name_team"):
            continue
        aliases = {normalized(move.get("name", "")), *map(normalized, move.get("aliases", []))}
        if not names.intersection(aliases):
            continue
        source_id = str(move.get("source_player_id", ""))
        if source_id and len(source_id) >= 8 and source_id != record["source_player_id"]:
            continue
        role = move.get("position_group")
        if role and role not in official[:120]:
            continue
        matches.append(move)
    latest = max(matches, key=lambda m: m["status_as_of"], default=None)
    return latest if latest and latest["kind"] == "departure" else None
