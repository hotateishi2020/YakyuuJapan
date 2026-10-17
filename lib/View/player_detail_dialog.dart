import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../tools/external_link.dart';
import '../logic/player_honors.dart';
import 'strength_contracts.dart' show contractSalaryLabel;

class PlayerDetailScope extends InheritedWidget {
  const PlayerDetailScope(
      {super.key, required this.org, required this.year, required super.child});
  final String org;
  final int year;
  static PlayerDetailScope? of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PlayerDetailScope>();
  @override
  bool updateShouldNotify(PlayerDetailScope old) =>
      org != old.org || year != old.year;
}

Future<void> showPlayerDetail(
    BuildContext context, Map<String, dynamic> player) async {
  final scope = PlayerDetailScope.of(context);
  await showDialog<void>(
      context: context,
      builder: (_) => PlayerDetailDialog(
          player: player,
          org: scope?.org ??
              ((int.tryParse('${player['id_league']}') ?? 0) >= 3
                  ? 'mlb'
                  : 'npb'),
          year: scope?.year ??
              int.tryParse('${player['int_year']}') ??
              DateTime.now().year));
}

class PlayerNameLink extends StatelessWidget {
  const PlayerNameLink({super.key, required this.player, required this.child});
  final Map<String, dynamic> player;
  final Widget child;
  @override
  Widget build(BuildContext context) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showPlayerDetail(context, player),
          child: child));
}

class PlayerDetailDialog extends StatefulWidget {
  const PlayerDetailDialog(
      {super.key, required this.player, required this.org, required this.year});
  final Map<String, dynamic> player;
  final String org;
  final int year;
  @override
  State<PlayerDetailDialog> createState() => _PlayerDetailDialogState();
}

class _PlayerDetailDialogState extends State<PlayerDetailDialog> {
  Map<String, dynamic> data = {};
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = widget.player;
      final q = <String, String>{
        'org': widget.org,
        'year': '${widget.year}',
        'name':
            '${p['name'] ?? p['name_full'] ?? p['name_player'] ?? p['player_name'] ?? ''}'
                .replaceAll(RegExp(r'\(.*\)$'), ''),
        if (p['id_player'] != null) 'id_player': '${p['id_player']}',
        if (p['source_player_id'] != null)
          'source_player_id': '${p['source_player_id']}',
        if (p['id_team'] != null) 'id_team': '${p['id_team']}'
      };
      final r = await http
          .get(Env.api('/player-detail').replace(queryParameters: q))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (mounted) setState(() => data = Map<String, dynamic>.from(d));
    } catch (_) {
      if (mounted) setState(() => error = '選手情報を取得できませんでした。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(s,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)));
  Widget source(dynamic url) => url == null || '$url'.isEmpty
      ? const SizedBox.shrink()
      : TextButton(
          onPressed: () => openExternalLink('$url'),
          child: const Text('出典', style: TextStyle(fontSize: 11)));
  Widget facts(Map<String, dynamic> values) =>
      Wrap(spacing: 10, runSpacing: 8, children: [
        for (final e in values.entries)
          SizedBox(
              width: 210,
              child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.blueGrey)),
                            Text(e.value == null || '${e.value}'.isEmpty
                                ? '未確認'
                                : '${e.value}')
                          ]))))
      ]);
  String hand(dynamic v) =>
      switch ('$v') { '0' => '右', '1' => '左', '2' => '両', _ => '未確認' };
  Widget statRows(List<Map<String, dynamic>> rows) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in rows)
          Tooltip(
              message: '${r['note'] ?? r['title']}\n${r['checked_at'] ?? ''}',
              child: SizedBox(
                  width: 145,
                  child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(children: [
                            Text('${r['title']}',
                                style: const TextStyle(fontSize: 11)),
                            Text('${r['stats'] ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 19, fontWeight: FontWeight.bold)),
                            source(r['source'])
                          ])))))
      ]);
  Widget recentTable(List<Map<String, dynamic>> games) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columns: [
          for (final label in [
            '日付',
            '対戦・結果',
            '打数',
            '安打',
            '打点',
            '投球回',
            '奪三振',
            '自責点',
            '打席結果',
            '出典'
          ])
            DataColumn(label: Text(label))
        ],
        rows: [
          for (final game in games)
            (() {
              final lines = listMapFromJson(game['lines']);
              int sum(String key) => lines.fold(0,
                  (n, row) => n + (num.tryParse('${row[key]}')?.toInt() ?? 0));
              final pitchers = lines.where((r) =>
                  (num.tryParse('${r['double_inning_pitch']}') ?? 0) > 0 ||
                  (num.tryParse('${r['int_pitch']}') ?? 0) > 0);
              return DataRow(cells: [
                DataCell(Text(
                    '${game['datetime_start']}'.split(RegExp('[ T]')).first)),
                DataCell(Text(
                    '${game['away']} ${game['score_away'] ?? '—'}–${game['score_home'] ?? '—'} ${game['home']}')),
                for (final key in ['int_batting', 'int_hit1', 'int_rbi'])
                  DataCell(Text(
                      lines.any((r) => r[key] != null) ? '${sum(key)}' : '—')),
                DataCell(Text(pitchers.isEmpty
                    ? '—'
                    : pitchers
                        .map((r) => '${r['double_inning_pitch']}')
                        .join(' / '))),
                for (final key in ['int_strike_out', 'int_runs_earned'])
                  DataCell(Text(pitchers.isEmpty ? '—' : '${sum(key)}')),
                DataCell(Text(listMapFromJson(game['plays'])
                    .map((r) => '${r['inning']}回 ${r['result']}')
                    .join(' / '))),
                DataCell(source(game['source'])),
              ]);
            })()
        ],
      ));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context),
        profile = map(data['profile']),
        roster = map(data['roster']),
        verified = map(data['verified']);
    final name =
        '${profile['name_full'] ?? widget.player['name'] ?? widget.player['name_player'] ?? widget.player['player_name'] ?? '選手詳細'}';
    final stats = listMapFromJson(data['season_stats']);
    final unique = <String, Map<String, dynamic>>{
      for (final r in stats) '${r['title']}': r
    };
    final honors = playerHonors(roster);
    return Dialog(
        insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 600 ? 8 : 40, vertical: 16),
        child: SizedBox(
            width: 1100,
            height: size.height - 32,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold))),
                    IconButton(
                        tooltip: '閉じる',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close))
                  ])),
              if (loading) const LinearProgressIndicator(),
              Expanded(
                  child: loading
                      ? const Center(child: Text('選手情報を取得しています'))
                      : error != null
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  Text(error!),
                                  TextButton(
                                      onPressed: load,
                                      child: const Text('再読み込み'))
                                ]))
                          : data['found'] == false
                              ? Center(child: Text('${data['message']}'))
                              : ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                      Wrap(
                                          spacing: 20,
                                          runSpacing: 12,
                                          children: [
                                            SizedBox(
                                                width: 450,
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      facts({
                                                        '所属': profile[
                                                            'name_team'],
                                                        '生年月日': profile[
                                                            'date_birth'],
                                                        'ポジション': profile[
                                                            'txt_position'],
                                                        '投打':
                                                            '${hand(profile['pitching'])}投げ／${hand(profile['batting'])}打ち',
                                                        '身長・体重':
                                                            '${profile['height'] ?? '—'}cm / ${profile['weight'] ?? '—'}kg',
                                                        '出身国': profile[
                                                            'birth_country'],
                                                        '出身地': profile[
                                                            'birth_place']
                                                      }),
                                                      source(profile['url'])
                                                    ]))
                                          ]),
                                      heading('${widget.year}年 シーズンスタッツ'),
                                      if (unique.isEmpty)
                                        const Text('この年度の成績は未取得です。')
                                      else
                                        statRows(unique.values.toList()),
                                      heading('直近25試合の出場成績'),
                                      Text('${data['recent_note'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.blueGrey)),
                                      if (listMapFromJson(data['recent_games'])
                                          .isEmpty)
                                        const Text('取得済みの出場成績がありません。'),
                                      recentTable(listMapFromJson(
                                          data['recent_games'])),
                                      heading('特徴・計測データ'),
                                      const Text(
                                          '公表時点・測定条件の分かる情報だけを表示します。未確認は未計測・非公表も含みます。',
                                          style: TextStyle(fontSize: 11)),
                                      facts({
                                        for (final key in [
                                          '選手の特徴',
                                          '特技・趣味',
                                          '打球速度',
                                          '二塁送球タイム',
                                          '一塁到達タイム',
                                          '遠投',
                                          '投球速度',
                                          '変化球の球種'
                                        ])
                                          key: map(verified[key])['value']
                                      }),
                                      for (final e in verified.entries)
                                        if (e.value is Map)
                                          Row(children: [
                                            Text(e.key),
                                            source(map(e.value)['source']),
                                            Text(
                                                '${map(e.value)['as_of'] ?? ''}',
                                                style: const TextStyle(
                                                    fontSize: 10))
                                          ]),
                                      heading('ゾーンごとの打率'),
                                      Text(map(verified['zone_batting']).isEmpty
                                          ? '投球位置データが未取得のため表示できません。'
                                          : '捕手視点・打席結果が確定した最終球のコース別。分母は打数。'),
                                      SizedBox(
                                          width: 300,
                                          child: Table(
                                              border: TableBorder.all(
                                                  color: Colors.black12),
                                              children: [
                                                for (var y = 0; y < 3; y++)
                                                  TableRow(children: [
                                                    for (var x = 0; x < 3; x++)
                                                      Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(14),
                                                          child: Text(
                                                              '${map(map(verified['zone_batting'])['zones'])['${y * 3 + x + 1}'] ?? '—'}',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center))
                                                  ])
                                              ])),
                                      source(map(
                                          verified['zone_batting'])['source']),
                                      heading('経歴・過去シーズン'),
                                      for (final c in listMapFromJson(
                                          roster['career_history']))
                                        ListTile(
                                            dense: true,
                                            title: Text('${c['team'] ?? ''}'),
                                            subtitle: Text(
                                                '${c['category'] ?? ''} ${c['detail'] ?? ''}'),
                                            trailing: source(c['source'])),
                                      SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(columns: [
                                            for (final c in [
                                              '年',
                                              '所属',
                                              '試合',
                                              '打席',
                                              '打率',
                                              '本塁打',
                                              '登板',
                                              '投球回',
                                              '防御率'
                                            ])
                                              DataColumn(label: Text(c))
                                          ], rows: [
                                            for (final c in listMapFromJson(
                                                data['careers']))
                                              DataRow(cells: [
                                                for (final k in [
                                                  'int_year',
                                                  'name_team',
                                                  'int_games',
                                                  'int_appearance',
                                                  'double_average_batting',
                                                  'int_homerun',
                                                  'int_pitching',
                                                  'double_inning',
                                                  'double_average_earned_runs'
                                                ])
                                                  DataCell(
                                                      Text('${c[k] ?? '—'}'))
                                              ])
                                          ])),
                                      heading('年俸・契約'),
                                      if (map(roster['contract_data']).isEmpty)
                                        const Text('確認済みの契約情報は未収録です。'),
                                      for (final salary in listMapFromJson(
                                              map(roster['contract_data'])[
                                                  'salary_history'])
                                          .where(
                                              (s) => s['year'] == widget.year))
                                        ListTile(
                                            title: Text(
                                                contractSalaryLabel(salary)),
                                            subtitle: Text(
                                                '${salary['detail'] ?? ''}'),
                                            trailing:
                                                source(salary['source_url'])),
                                      for (final c in listMapFromJson(map(
                                          roster['contract_data'])['periods']))
                                        ListTile(
                                            title: Text(
                                                '${c['start_year'] ?? ''}–${c['end_year'] ?? ''} ${c['total_label'] ?? ''}'),
                                            subtitle:
                                                Text('${c['detail'] ?? ''}'),
                                            trailing: source(c['source_url'])),
                                      heading('今シーズンの起用'),
                                      for (final p in listMapFromJson(map(
                                          data['usage'])['pitching_workload']))
                                        facts({
                                          '登板': p['appearances'],
                                          '先発': p['starts'],
                                          '先発割合': (num.tryParse(
                                                          '${p['appearances']}') ??
                                                      0) >
                                                  0
                                              ? '${((num.tryParse('${p['starts']}') ?? 0) * 100 / num.parse('${p['appearances']}')).toStringAsFixed(1)}%'
                                              : null
                                        }),
                                      for (final p in listMapFromJson(
                                          map(data['usage'])['positions']))
                                        ListTile(
                                            dense: true,
                                            title: Text(
                                                '${p['slot']}：${p['count']}試合'),
                                            subtitle: Text((num.tryParse(
                                                            '${p['total']}') ??
                                                        0) >
                                                    0
                                                ? '起用割合 ${((num.tryParse('${p['count']}') ?? 0) * 100 / num.parse('${p['total']}')).toStringAsFixed(1)}%'
                                                : '割合の分母は未確認')),
                                      if (map(data['usage']).values.every(
                                          (v) => v is! List || v.isEmpty))
                                        const Text('起用情報は未取得です。'),
                                      heading('功績'),
                                      if (honors.isEmpty)
                                        const Text('確認済みの功績データは未収録です。'),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            for (final h in honors)
                                              Chip(
                                                  label: Text(
                                                      '${h['year'] ?? ''} ${h['label']}'))
                                          ]),
                                      const SizedBox(height: 20)
                                    ]))
            ])));
  }
}
