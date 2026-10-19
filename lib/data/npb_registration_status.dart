// Effective seasons verified independently of FA acquisition dates.
const npbRegistrationExemptions = <Map<String, dynamic>>[
  {
    'player_key': 'npb:13715132',
    'year': 2024,
    'source_url':
        'https://www.hicbc.com/magazine/article/?id=dragons-post-8568',
    'detail': '2024年から外国人選手枠の適用対象外。',
  },
  {
    'player_key': 'npb:03505136',
    'year': 2026,
    'source_url':
        'https://www.nikkansports.com/baseball/news/202601300001080.html',
    'detail': '2025年に国内FA権を取得し、2026年から外国人選手枠の適用対象外。',
  },
  {
    'player_key': 'npb:63965134',
    'year': 2026,
    'source_url': 'https://www.nikkan-gendai.com/articles/view/sports/373962',
    'detail': '2025年に国内FA権を取得し、2026年から外国人選手枠の適用対象外。',
  },
];

// Reports are seasonal, not evidence that the club has approved a transfer.
final npbPostingReports = <Map<String, dynamic>>[
  for (final name in ['佐藤輝明', '才木浩人', '石井大智'])
    {
      'name': name,
      'year': 2026,
      'status': 'rumored',
      'source_url':
          'https://www.nikkansports.com/baseball/news/202601310001244.html',
      'detail': 'MLB挑戦の希望を球団へ伝えたとの報道。ポスティングの容認・移籍は未確定。',
    },
];
