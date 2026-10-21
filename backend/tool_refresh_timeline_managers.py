"""Refresh season-specific managers from NPB's official franchise histories."""
import concurrent.futures
import datetime
import html
import json
from pathlib import Path
import re
import urllib.request

CODES = ['g', 't', 'db', 'c', 'd', 's', 'h', 'f', 'm', 'l', 'e', 'b']

def parse_managers(page):
    result = {}
    for row in re.findall(r'<tr\b[^>]*class="teylist"[^>]*>(.*?)</tr>', page, re.S):
        cells = re.findall(r'<td\b[^>]*>(.*?)</td>', row, re.S)
        if len(cells) < 3:
            continue
        def text(value):
            value = re.sub(r'<br\s*/?>', '／', value, flags=re.I)
            return re.sub(r'\s+', '', html.unescape(re.sub(r'<[^>]+>', '', value)))
        match = re.match(r'^(\d{4})', text(cells[0]))
        names = text(cells[1]).strip('／')
        if not match or not names:
            continue
        year = match[1]
        old = result.get(year, '').split('／') if year in result else []
        result[year] = '／'.join(dict.fromkeys(old + names.split('／')))
    return result

def fetch(code):
    url = f'https://npb.jp/bis/teams/yearly_{code}.html'
    with urllib.request.urlopen(url, timeout=30) as response:
        rows = parse_managers(response.read().decode('utf-8'))
    if not rows:
        raise ValueError(f'No manager records: {url}')
    return code, {'source': url, 'years': rows}

if __name__ == '__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        clubs = dict(pool.map(fetch, CODES))
    path = Path(__file__).parent / 'data/timeline-managers-npb.json'
    path.write_text(json.dumps({'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'clubs': clubs}, ensure_ascii=False, indent=2) + '\n')
    print(f'Saved {sum(len(c["years"]) for c in clubs.values())} club-seasons')
