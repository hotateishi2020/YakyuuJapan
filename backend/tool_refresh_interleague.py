"""Refresh confirmed full-season interleague leaders from NPB's official tables."""
import concurrent.futures, datetime, html, json, re, urllib.request, time
from pathlib import Path

def fetch(year):
    url = f'https://npb.jp/bis/{year}/stats/std_inter.html'
    try:
        text = urllib.request.urlopen(url, timeout=25).read().decode('utf-8')
        rows = re.findall(r'<tr[^>]*class="ststats"[^>]*>(.*?)</tr>', text, re.S)
        cells = [[html.unescape(re.sub('<[^>]+>', '', c)).strip() for c in re.findall(r'<td[^>]*>(.*?)</td>', r, re.S)] for r in rows]
        needed = 36 if year <= 2006 else 24 if year <= 2014 else 18
        if not cells:
            names = re.findall(r'<td[^>]*class="stdTeam"[^>]*>(.*?)</td>', text, re.S)
            if len(names) == 12 and '全日程終了' in text:
                ordered = [html.unescape(re.sub('<[^>]+>', '', name)).strip() for name in names]
                return str(year), {'name': ordered[0], 'source': url, 'standings': [{'name': name, 'rank': i + 1} for i, name in enumerate(ordered)]}
        if len(cells) != 12 or any(int(c[1]) != needed for c in cells):
            return None
        return str(year), {'name': cells[0][0], 'source': url, 'standings': [{'name': row[0], 'rank': i + 1} for i, row in enumerate(cells)]}
    except Exception as error:
        print(year, error)
        return None

if __name__ == '__main__':
    path = Path(__file__).parent / 'data/interleague_champions.json'
    data = json.loads(path.read_text()) if path.exists() else {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(fetch, range(2005, datetime.date.today().year + 1)):
            if result: data[result[0]] = result[1]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('Confirmed seasons:', len(data))
