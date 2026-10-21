"""Refresh factual NPB achievement tables; preserve reviewed historical events."""
import html
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / 'data/baseball-timeline.json'

def refresh():
    entries = json.loads(OUTPUT.read_text()) if OUTPUT.exists() else []
    sources = {'triplethree': 'トリプルスリー', 'triplecrown': '三冠王'}
    for slug, label in sources.items():
        url = f'https://npb.jp/history/alltime/{slug}.html'
        page = urllib.request.urlopen(url, timeout=30).read().decode('utf-8')
        parsed = []
        for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>', page, re.S):
            cells = [html.unescape(re.sub('<[^>]+>', '', c)).strip() for c in
                     re.findall(r'<t[dh]\b[^>]*>(.*?)</t[dh]>', row, re.S)]
            if len(cells) < 6 or not re.match(r'^\d{4}', cells[2]):
                continue
            year = int(cells[2][:4])
            phase = '秋季 ' if '秋' in cells[2] else ''
            text = f'{phase}{cells[0]}（{cells[1]}）{label}：打率{cells[3]}・{cells[4]}本塁打・{cells[5]}' + ('盗塁' if slug == 'triplethree' else '打点')
            parsed.append(dict(org='npb', year=year, category='records', text=text, source=url))
        if not parsed:
            raise RuntimeError(f'No achievement rows: {url}')
        entries = [e for e in entries if e['source'] != url] + parsed
    entries.sort(key=lambda e: (e['org'], e['year'], e['category'], e['text']))
    OUTPUT.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + '\n')
    print(f'Registered {len(entries)} timeline events')

if __name__ == '__main__':
    refresh()
