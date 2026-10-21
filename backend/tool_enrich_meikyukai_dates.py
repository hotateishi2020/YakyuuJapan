"""Enrich existing official membership rows with sourced chronological sort keys.

Usage: python tool_enrich_meikyukai_dates.py downloaded-meikyukai-wikipedia.html
Requires beautifulsoup4. Does not add/remove members or treat page publication
dates as membership dates. Achievement dates are explicitly marked as proxies.
"""
import json
import pathlib
import re
import sys

from bs4 import BeautifulSoup

ROOT = pathlib.Path(__file__).resolve().parent
SOURCE = 'https://ja.wikipedia.org/wiki/日本プロ野球名球会'
FOUNDING = '1978-07-24'


def normalize(value):
    return re.sub(r'[\s・･.]', '', value)


def enrich(members, html):
    soup = BeautifulSoup(html, 'html.parser')
    for element in soup.select('span[style*="visibility:hidden"],sup'):
        element.decompose()
    dates = {}
    for table in soup.select('table'):
        rows = table.select('tr')
        if not rows:
            continue
        headers = [c.get_text('', strip=True) for c in
                   rows[0].find_all(['th', 'td'], recursive=False)]
        label = next((s for s in ['入会認定日', '達成日'] if s in headers), None)
        if label is None:
            continue
        for row in rows[1:]:
            cells = row.find_all(['th', 'td'], recursive=False)
            if len(cells) != len(headers):
                continue
            match = re.search(r'(\d{4})年(\d+)月(\d+)日',
                              cells[headers.index(label)].get_text('', strip=True))
            if not match:
                continue
            date = f'{int(match[1]):04}-{int(match[2]):02}-{int(match[3]):02}'
            for link in cells[0].select('a'):
                dates[normalize(link.get_text('', strip=True))] = (date, label)
    aliases = {
        'アレックスラミレス': 'A・ラミレス',
        '鈴木一朗(イチロー)': '鈴木一朗（イチロー）',
        '山本昌広': '山本昌',
        'ライデルマルティネス': 'R.マルティネス',
    }
    missing = []
    for member in members:
        name = normalize(member['name'])
        resolved = dates.get(normalize(aliases.get(name, name)))
        if not resolved:
            missing.append(member['name'])
            continue
        date, label = resolved
        member['membership_date_source'] = SOURCE
        if label == '入会認定日':
            member['joined_date'] = date
            member['membership_sort_date'] = date
            member['membership_date_basis'] = '特例入会認定日'
        else:
            member['qualification_date'] = date
            member['membership_sort_date'] = max(date, FOUNDING)
            member['membership_date_basis'] = (
                '創設時会員' if date < FOUNDING else '入会基準達成日による順序')
        # The save criterion was introduced in December 2003, after both
        # pitchers had achieved 250 saves. Do not backdate their membership.
        if name in ('佐々木主浩', '高津臣吾'):
            member['membership_sort_date'] = '2003-12'
            member['membership_date_basis'] = '250セーブ基準追加時の入会'
            member['membership_date_source'] = 'https://allabout.co.jp/gm/gc/212391/'
        if member.get('joined_date'):
            member['membership_sort_date'] = member['joined_date']
    if missing:
        raise ValueError(f'Missing membership chronology: {missing}')
    members.sort(key=lambda r: (
        r['membership_sort_date'], r.get('qualification_date', ''),
        normalize(r['name'])))


if __name__ == '__main__':
    target = ROOT / 'data/baseball-catalog.json'
    data = json.loads(target.read_text())
    enrich(data['members'], pathlib.Path(sys.argv[1]).read_text())
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(f"Enriched {len(data['members'])} members")
