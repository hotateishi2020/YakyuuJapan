import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../tools/external_link.dart';
import '../logic/club_analysis.dart';

class ClubHubBoard extends StatefulWidget {
  const ClubHubBoard({super.key, required this.org, required this.year, required this.teams, required this.view, required this.teamSection});
  final OrgConfig org;
  final int year, view;
  final List<Map<String, dynamic>> teams;
  final Widget Function(int, Map<String, dynamic>) teamSection;
  @override
  State<ClubHubBoard> createState() => _ClubHubBoardState();
}

class _ClubHubBoardState extends State<ClubHubBoard> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String? _selected;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClubHubBoard old) {
    super.didUpdateWidget(old);
    if (old.org.kind != widget.org.kind || old.year != widget.year) {
      _data = {};
      _selected = null;
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await http.get(Env.api('/club-hub?org=${widget.org.kind.name}&year=${widget.year}')).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw const FormatException('取得失敗');
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is! Map) throw const FormatException('データ形式');
      if (mounted && request == _request) {
        setState(() => _data = Map<String, dynamic>.from(d));
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = '球団の公式情報を取得できませんでした');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Widget _source(dynamic url, {String label = '公式情報'}) => url == null ? const SizedBox.shrink() : TextButton(onPressed: () => openExternalLink('$url'), child: Text(label, style: const TextStyle(fontSize: 11)));
  List<Map<String, dynamic>> get _clubs => listMapFromJson(_data['clubs']);
  Widget _analysis() {
    final rows = analyzeClubs(widget.teams, widget.year);
    return ListView(children: [
      const Padding(padding: EdgeInsets.all(8), child: Text('取得済み成績による団体内の相対評価（S → A → B → C → D → E → F → G）。打撃：打席加重OPS／走力：(盗塁−2×盗塁死)÷打席／守備：位置別UZR合計／投手：主な起用が先発・救援の投手別WHIPを投球回で加重。中継ぎには抑えを含みます。走力は盗塁の参考評価で、進塁・走塁全体を網羅しません。守備はUZR取得選手の範囲に限り、未計測を0扱いしません。未計測は —。平均年齢は守備位置ごとの最多起用野手（重複除外）、当年は本日時点。')),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columnSpacing: 22, columns: [
            for (final c in ['球団', ...analysisCategories, 'レギュラー平均年齢', '強み', '弱み']) DataColumn(label: Text(c))
          ], rows: [
            for (final row in rows)
              DataRow(cells: [
                DataCell(Text('${row['name_team']}')),
                for (final c in analysisCategories)
                  DataCell(Tooltip(
                      message: '${row['metrics'][c] ?? '未計測'}',
                      child: Text('${row['grades'][c]}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: ['S', 'A', 'B'].contains(row['grades'][c])
                                  ? Colors.blue.shade800
                                  : ['E', 'F', 'G'].contains(row['grades'][c])
                                      ? Colors.red.shade800
                                      : Colors.black87)))),
                DataCell(Text(row['regular_age'] == null ? '—' : '${(row['regular_age'] as double).toStringAsFixed(1)}歳 (${row['age_count']}/${row['regular_count']}人)')),
                DataCell(Text('${row['strengths']}')),
                DataCell(Text('${row['weaknesses']}'))
              ])
          ]))
    ]);
  }

  Widget _staff() {
    const roles = ['監督', 'ヘッド・総合', '投手', '打撃', 'バッテリー', '内野守備', '外野守備', '走塁', '育成・その他'];
    int level(Map<String, dynamic> p) {
      final explicit = int.tryParse('${p['level']}');
      if (explicit != null) return explicit;
      final role = '${p['role']}';
      for (final pair in [(4, '四'), (3, '三'), (2, '二'), (1, '一')]) {
        if (role.contains('${pair.$1}軍') || role.contains('${pair.$2}軍')) return pair.$1;
      }
      return role.contains('ファーム') ? 2 : 1;
    }
    List<String> duties(Map<String, dynamic> p) {
      final role = '${p['role']}';
      if (role.contains('監督')) return ['監督'];
      final found = <String>[
        if (RegExp('ヘッド|総合|チーフ|オフェンス|ディフェンス').hasMatch(role)) 'ヘッド・総合',
        if (role.contains('投手')) '投手', if (role.contains('打撃')) '打撃',
        if (role.contains('バッテリー')) 'バッテリー',
        if (role.contains('内野')) '内野守備', if (role.contains('外野')) '外野守備',
        if (role.contains('走塁')) '走塁',
      ];
      return found.isEmpty ? ['育成・その他'] : found;
    }
    Widget people(Iterable<Map<String, dynamic>> list) => Padding(padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (list.isEmpty) const Text('—'),
        for (final p in list) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${p['role']}', style: const TextStyle(fontSize: 11)), _source(p['source']),
        ]),
      ]));
    return ListView(children: [
      const Padding(padding: EdgeInsets.all(8), child: Text('公式登録の軍・担当別。兼任は各担当列に表示。— は未収録。')),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Table(
        defaultColumnWidth: const FixedColumnWidth(150), border: TableBorder.all(color: Colors.black26),
        children: [
          TableRow(decoration: BoxDecoration(color: widget.org.tabColor.withValues(alpha: .15)), children: [
            for (final title in ['球団・軍', ...roles]) Padding(padding: const EdgeInsets.all(8), child: Text(title)),
          ]),
          for (final club in _clubs)
            for (var army = 1; army <= 4; army++) TableRow(children: [
              Padding(padding: const EdgeInsets.all(8), child: Text('${club['name']}　$army軍')),
              for (final duty in roles) people(listMapFromJson(club['staff']).where((p) =>
                !['オーナー','球団社長','スカウト'].contains(p['category']) && level(p) == army && duties(p).contains(duty))),
            ]),
        ],
      )),
      for (final club in _clubs) ...[
        Padding(padding: const EdgeInsets.all(8), child: Text('${club['name']}　オーナー・球団社長・スカウト')),
        people(listMapFromJson(club['staff']).where((p) => ['オーナー','球団社長','スカウト'].contains(p['category']))),
      ],
    ]);
  }

  Widget _training({String? teamName}) {
    final groups = sortedTrainingGroups(_data['training_groups']).where((g) => teamName == null || listMapFromJson(g['members']).any((p) => teamName.contains('${p['team']}'))).toList();
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(8), child: Text('${widget.year}年シーズン前の自主トレ。公式に参加が確認できたメンバー数の多い順です。')),
      if (groups.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('この年度の公式発表データはまだ収録されていません。')),
      for (final group in groups)
        Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${group['name']}　${listMapFromJson(group['members']).length}人', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${group['location'] ?? ''} ${group['period'] ?? ''}'),
                  Wrap(spacing: 8, children: [for (final p in listMapFromJson(group['members'])) Chip(label: Text('${p['name']} (${p['team'] ?? ''})'))]),
                  _source(group['source'])
                ])))
    ]);
  }

  Widget _team() {
    if (widget.teams.isEmpty) return const Center(child: Text('戦力情報がありません'));
    final team = widget.teams.firstWhere((t) => '${t['id_team']}' == _selected, orElse: () => widget.teams.first);
    final club = _clubs.where((c) => c['code'] == npbClubKey(team)).firstOrNull;
    final sponsors = listMapFromJson(club?['sponsors']);
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(8), child: DropdownButton<String>(isExpanded: true, value: '${team['id_team']}', items: [for (final t in widget.teams) DropdownMenuItem(value: '${t['id_team']}', child: Text('${t['name_team']}'))], onChanged: (v) => setState(() => _selected = v))),
      for (final e in const <int, String>{0: '貢献度', 1: '選手起用', 2: '主力選手', 3: '選手一覧', 4: '契約', 5: 'ドラフト', 6: '経歴'}.entries) _TeamSection(key: ValueKey('${team['id_team']}-${e.key}'), title: e.value, builder: () => widget.teamSection(e.key, team)),
      _TeamSection(title: 'チーム分析', height: null, builder: () => _singleAnalysis(team)),
      if (club != null) _TeamSection(title: '首脳・スタッフ', height: null, builder: () => Column(children: [for (final p in listMapFromJson(club['staff'])) ListTile(dense: true, title: Text('${p['name']}'), subtitle: Text('${p['role']}'), trailing: _source(p['source']))])),
      _TeamSection(title: '自主トレ', height: 350, builder: () => _training(teamName: '${team['name_team']}')),
      const Padding(padding: EdgeInsets.all(12), child: Text('スポンサー・広告', style: TextStyle(fontWeight: FontWeight.bold))),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('公式サイトで確認できた協賛先を掲載しています。広告の全件網羅を示すものではありません。', style: TextStyle(fontSize: 11))),
      if (sponsors.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('この年度の公式スポンサー情報は未収録です。')),
      Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final sponsor in sponsors) SizedBox(width: 170, child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [if (sponsor['logo'] != null) Image.network('${sponsor['logo']}'.startsWith('/') ? Env.api('${sponsor['logo']}').toString() : '${sponsor['logo']}', height: 55, width: 150, fit: BoxFit.contain, errorBuilder: (context, error, stack) => const SizedBox(height: 55, child: Icon(Icons.business))), Text('${sponsor['name']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)), Text('${sponsor['category'] ?? '公式スポンサー'}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)), _source(sponsor['source'])]))))
          ]))
    ]);
  }

  Widget _singleAnalysis(Map<String, dynamic> team) {
    final row = analyzeClubs(widget.teams, widget.year).firstWhere((r) => r['id_team'] == team['id_team']);
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, children: [for (final c in analysisCategories) Chip(label: Text('$c ${row['grades'][c]}'))]),
          Text('強み：${row['strengths']}\n弱み：${row['weaknesses']}'),
          const Text('評価の算出方法は「分析」タブを参照', style: TextStyle(fontSize: 11))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.view == 10) return _analysis();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Row(children: [Expanded(child: Text(_error!)), TextButton(onPressed: _load, child: const Text('再読み込み'))]),
      if (_data['checked_at'] != null) Text('公式情報確認：${_data['checked_at']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
      if (!_loading && _clubs.isEmpty && widget.view == 8) const Text('この団体・年度の首脳情報は未収録です。'),
      Expanded(
          child: widget.view == 7
              ? _team()
              : widget.view == 8
                  ? _staff()
                  : _training())
    ]);
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({super.key, required this.title, required this.builder, this.height = 520});
  final String title;
  final Widget Function() builder;
  final double? height;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(header: true, child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      )),
      SizedBox(height: height, child: builder()),
    ],
  );
}
