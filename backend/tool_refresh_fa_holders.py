"""Cache official FA holders, excluding players who exercised that right."""
import json
import re
from datetime import date
from pathlib import Path
import subprocess
from tool_refresh_fa_rights import Tree

def fetch(url):
    response = subprocess.check_output(['curl', '--silent', '--show-error', '--location', '--max-time', '30', '-A', 'Mozilla/5.0', '-w', '\n%{http_code}', url]).decode('utf-8')
    body, status = response.rsplit('\n', 1)
    if status == '404': raise FileNotFoundError(url)
    if status != '200': raise RuntimeError(f'HTTP {status}')
    return Tree(body).root


def holders(doc, year, filed):
    result = []
    for row in doc.all('tr'):
        if not any(c.tag == 'th' and 'fateam' in c.attrs.get('class', '') for c in row.children):
            continue
        cells = [c for c in row.children if c.tag == 'td']
        if len(cells) != 4:
            raise ValueError('Unexpected FA table format')
        for i, cell in enumerate(cells):
            for a in cell.all('a'):
                match = re.search(r'/players/(\d+)\.html', a.attrs.get('href', ''))
                if match and match[1] not in filed:
                    result.append(dict(player_key='npb:' + match[1], year=year,
                        type='domestic' if i < 2 else 'international',
                        source_url=f'https://npb.jp/announcement/{year}/fa_qualified.html'))
    return result


def main():
    year = date.today().year
    try:
        doc = fetch(f'https://npb.jp/announcement/{year}/fa_qualified.html')
    except FileNotFoundError:
        year -= 1
        doc = fetch(f'https://npb.jp/announcement/{year}/fa_qualified.html')
    filed_doc = fetch(f'https://npb.jp/announcement/{year}/fa_filed.html')
    filed = {m[1] for a in filed_doc.all('a') if (m := re.search(r'/players/(\d+)\.html', a.attrs.get('href', '')))}
    rows = holders(doc, year, filed)
    if not rows: raise ValueError('Empty FA holder list')
    Path('lib/data/npb_fa_holders.dart').write_text('// Official holders excluding exercised rights. Refreshed '+str(date.today())+'\nconst npbFaHolders = <Map<String, dynamic>>'+json.dumps(rows, ensure_ascii=False, indent=2)+';\n')
    print(f'FA holders: {len(rows)}, official season: {year}')

if __name__ == '__main__': main()
