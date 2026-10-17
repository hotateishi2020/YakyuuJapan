/// Season-specific leadership; never carry a role into another season or club.
/// 2026 roster checked against the linked announcements/list on 2026-10-16.
class RosterLeadership {
  const RosterLeadership(this.teams, this.names, this.label,
      {this.source = 'https://base-info.com/leader', this.detail = ''});
  final List<String> teams;
  final List<String> names;
  final String label;
  final String source;
  final String detail;
}

const _roles2026 = <RosterLeadership>[
  RosterLeadership(['ソフトバンク', 'ホークス'], ['栗原陵矢'], '選手会長'),
  RosterLeadership(['日本ハム', 'ファイターズ'], ['清宮幸太郎'], '選手会長'),
  RosterLeadership(['オリックス', 'バファローズ'], ['若月健矢'], '選手会長'),
  RosterLeadership(['楽天', 'イーグルス'], ['早川隆久'], '選手会長'),
  RosterLeadership(['西武', 'ライオンズ'], ['外崎修汰'], '選手会長'),
  RosterLeadership(['ロッテ', 'マリーンズ'], ['中村奨吾'], '選手会長'),
  RosterLeadership(['阪神', 'タイガース'], ['村上頌樹'], '選手会長'),
  RosterLeadership(['DeNA', 'ベイスターズ'], ['東克樹'], '選手会長'),
  RosterLeadership(['巨人', '読売', 'ジャイアンツ'], ['吉川尚輝'], '選手会長'),
  RosterLeadership(['中日', 'ドラゴンズ'], ['藤嶋健人'], '選手会長'),
  RosterLeadership(['広島', 'カープ'], ['島内颯太郎'], '選手会長'),
  RosterLeadership(['ヤクルト', 'スワローズ'], ['古賀優大'], '選手会長'),
  RosterLeadership(['ロッテ', 'マリーンズ'], ['ソト', 'ネフタリ・ソト', 'N.ソト'], 'キャプテン',
      source: 'https://www.marines.co.jp/news/detail/202600782660.html'),
  RosterLeadership(['阪神', 'タイガース'], ['坂本誠志郎'], 'キャプテン',
      source: 'https://www.hanshintigers.jp/news/topics/info_11280.html'),
  RosterLeadership(['DeNA', 'ベイスターズ'], ['筒香嘉智'], 'キャプテン',
      source: 'https://sp.baystars.co.jp/news/2026/01/0120_03.php'),
  RosterLeadership(['巨人', '読売', 'ジャイアンツ'], ['岸田行倫'], 'キャプテン',
      source: 'https://prtimes.jp/main/html/rd/p/000000926.000071317.html'),
  RosterLeadership(['中日', 'ドラゴンズ'], ['高橋宏斗'], 'キャプテン', detail: '投手',
      source: 'https://www.nikkansports.com/baseball/news/202512220000744.html'),
  RosterLeadership(['中日', 'ドラゴンズ'], ['岡林勇希'], 'キャプテン', detail: '野手',
      source: 'https://www.nikkansports.com/baseball/news/202512220000744.html'),
];

String _normalize(String value) => value.replaceAll(RegExp(r'[\s　・]'), '').replaceAll('髙', '高').replaceAll('ＤｅＮＡ', 'DeNA').toLowerCase();

List<RosterLeadership> rosterLeadershipRoles(Map<String, dynamic> player, Map<String, dynamic> team, int year) {
  if (year != 2026) return const [];
  final name = _normalize('${player['name'] ?? ''}');
  final club = _normalize('${team['name_team'] ?? ''} ${team['name_short'] ?? ''}');
  return _roles2026.where((role) => role.names.any((n) => _normalize(n) == name) &&
      role.teams.any((t) => club.contains(_normalize(t)))).toList();
}
