"""Refresh the official historical league winners used by ChampionshipSummary."""
import json
import re
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

SOURCE = 'https://npb.jp/bis/yearly/index.html'

class Winners(HTMLParser):
    def __init__(self):
        super().__init__()
        self.href = ''
        self.text = ''
        self.years = {}

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.href = dict(attrs).get('href', '')
            self.text = ''

    def handle_data(self, text):
        self.text += text

    def handle_endtag(self, tag):
        if tag != 'a':
            return
        match = re.search(r'(central|pacific)league_?(\d{4})', self.href)
        name = self.text.strip()
        if match and name and not name.isdigit():
            self.years.setdefault(match[2], {})[match[1]] = name

if __name__ == '__main__':
    parser = Winners()
    with urllib.request.urlopen(SOURCE, timeout=30) as response:
        parser.feed(response.read().decode('utf-8'))
    if len(parser.years) < 75 or any(len(v) != 2 for v in parser.years.values()):
        raise ValueError('Incomplete official championship history; existing file retained')
    target = Path(__file__).parent / 'data/npb_league_champions.json'
    temp = target.with_suffix('.tmp')
    temp.write_text(json.dumps({'source': SOURCE, 'years': parser.years}, ensure_ascii=False, indent=2), encoding='utf-8')
    temp.replace(target)
    print(f'{len(parser.years)} seasons saved')
