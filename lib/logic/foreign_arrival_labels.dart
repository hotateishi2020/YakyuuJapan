import '../tools/json_utils.dart';

// 2026 offseason acquisitions (exclude same-team renewals):
// https://www.nikkansports.com/baseball/news/202512150000546.html
// In-season additions:
// https://nennpo.com/2026-foreign/
const foreignArrivals2026 = [
  (team: '巨人', name: 'ウィットリー', key: 'npb:53355152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '巨人', name: 'ダルベック', key: 'npb:63565152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '巨人', name: 'マタ', key: 'npb:53755152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '巨人', name: 'ハワード', key: 'npb:23725150', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '阪神', name: 'ディベイニー', key: 'npb:83585152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '阪神', name: 'モレッタ', key: 'npb:03705152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '阪神', name: 'ルーカス', key: 'npb:73975152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '阪神', name: 'ラグズデール', key: 'npb:63765152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '阪神', name: 'セベリーノ', key: 'npb:53055152', period: '今季', method: 'FA移籍', source: ''),
  (team: '阪神', name: 'ガルシア', key: 'npb:73075152', period: '今季', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'デュプランティエ', key: 'npb:13715150', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'レイノルズ', key: 'npb:93995152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'ルイーズ', key: 'npb:53955152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'コックス', key: 'npb:83385152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'ヒュンメル', key: 'npb:13715152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'ビド', key: 'npb:13015152', period: '今季', method: 'FA移籍', source: ''),
  (team: 'DeNA', name: 'エンカーナシオン', key: 'npb:33035152', period: '今季', method: 'FA移籍', source: ''),
  (team: '中日', name: 'サノー', key: 'npb:73575152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '中日', name: 'アブレウ', key: 'npb:73575159', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '広島', name: 'ターノック', key: 'npb:43545152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ヤクルト', name: 'ウォルターズ', key: 'npb:63965150', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ヤクルト', name: 'リランソ', key: 'npb:13915152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ヤクルト', name: 'キハダ', key: 'npb:63365152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ソフトバンク', name: '徐若熙', key: 'npb:23525152', period: '昨オフ', method: 'ポスティング', source: ''),
  (team: 'ソフトバンク', name: 'モレノ', key: 'npb:23725152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ソフトバンク', name: 'ラトリッジ', key: 'npb:23025152', period: '今季', method: 'FA移籍', source: ''),
  (team: '日本ハム', name: 'ラオ', key: 'npb:43745152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '日本ハム', name: 'カストロ', key: 'npb:43945152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'オリックス', name: 'シーモア', key: 'npb:93595152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'オリックス', name: 'ジェリー', key: 'npb:03505152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '楽天', name: 'マッカスカー', key: 'npb:73775152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '楽天', name: 'コントレラス', key: 'npb:53555152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '楽天', name: 'ウレーニャ', key: 'npb:73375152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '西武', name: '林安可', key: 'npb:33935152', period: '昨オフ', method: 'ポスティング', source: ''),
  (team: '西武', name: 'ワイナンス', key: 'npb:23925152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '西武', name: 'カナリオ', key: 'npb:23325152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '西武', name: 'ゴンザレス', key: 'npb:33535152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '西武', name: 'オリバー', key: 'npb:93395152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: '西武', name: 'コルニエル', key: 'npb:13515152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ロッテ', name: 'ジャクソン', key: 'npb:43745159', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ロッテ', name: 'カスティーヨ', key: 'npb:03305152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ロッテ', name: 'ロング', key: 'npb:03905152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ロッテ', name: 'ラドニー', key: 'npb:83785152', period: '昨オフ', method: 'FA移籍', source: ''),
  (team: 'ロッテ', name: 'ルケーシー', key: 'npb:93095152', period: '今季', method: 'FA移籍', source: ''),
  (team: '西武', name: 'ムサ', key: 'npb:93795152', period: '昨オフ', method: 'FA移籍', source: 'https://www.seibulions.co.jp/pressrelease/202511/all/index.html'),
  (team: '西武', name: 'フレッド', key: 'npb:33735152', period: '昨オフ', method: 'FA移籍', source: 'https://www.seibulions.co.jp/pressrelease/202511/all/index.html'),
  (team: '西武', name: 'カルロス', key: 'npb:43345152', period: '昨オフ', method: 'FA移籍', source: 'https://www.seibulions.co.jp/pressrelease/202511/all/index.html'),
  (team: '西武', name: 'モーレ', key: 'npb:03005152', period: '今季', method: 'FA移籍', source: 'https://pacificleague.com/news/2026/7/85005'),
  (team: '西武', name: 'アポンテ', key: 'npb:63065152', period: '今季', method: 'FA移籍', source: 'https://pacificleague.com/news/2026/8/10053863'),
  (team: '広島', name: 'アリア', key: 'npb:63965152', period: '昨オフ', method: 'FA移籍', source: 'https://news.mynavi.jp/article/20260313-4215242/'),
  (team: '日本ハム', name: 'リン', key: 'npb:83985152', period: '昨オフ', method: 'FA移籍', source: 'https://npb.jp/bis/teams/rst_f.html'),
  (team: '楽天', name: 'フロリモン', key: 'npb:43045152', period: '今季', method: 'FA移籍', source: 'https://www.rakuteneagles.jp/?iref=sp_rellink_01'),
];

/// Fill display metadata even when the server returns an older roster snapshot.
/// Only known acquisitions qualify; birthplace alone is never evidence of a move.
List<Map<String, dynamic>> withForeignArrivalLabels(
    List<Map<String, dynamic>> teams, int year, {required bool npb}) {
  if (!npb) return teams;
  String normalize(dynamic value) => '${value ?? ''}'.replaceAll(RegExp(r'[\s　・．.]'), '');
  return [for (final team in teams) {
    ...team,
    'roster': [for (final original in listMapFromJson(team['roster'])) (() {
      final player = Map<String, dynamic>.from(original);
      final known = year == 2026 ? foreignArrivals2026.where((e) =>
        e.team == team['name_team'] &&
        ((e.key.isNotEmpty && e.key == player['player_key']) ||
          normalize(e.name) == normalize(player['name']))).firstOrNull : null;
      final method = '${player['move_method'] ?? ''}';
      if (method == '新外国人') player['move_method'] = 'FA移籍';
      if (known == null) return player;
      // Keep a subsequent trade/active draft and its date intact.
      if (method.isNotEmpty && method != '新外国人' && method != 'FA移籍') return player;
      player['move_method'] = known.method;
      player['move_method_year'] ??= year;
      if ('${player['move_method_as_of'] ?? player['arrival_as_of'] ?? ''}'.isEmpty) {
        player['move_method_period'] = known.period;
      }
      if (player['new_arrival'] == null && player['departure_confirmed'] != true) {
        player['new_arrival'] = true;
        player['arrival_year'] = year;
        player['arrival_period'] = known.period;
      }
      player['arrival_label_source'] = known.source.isNotEmpty ? known.source : known.period == '昨オフ'
          ? 'https://www.nikkansports.com/baseball/news/202512150000546.html'
          : 'https://nennpo.com/2026-foreign/';
      return player;
    })()],
  }];
}
