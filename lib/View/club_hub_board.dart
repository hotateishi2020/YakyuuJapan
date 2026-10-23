import '../widgets/navigation_picker.dart';
import '../widgets/collapsible_menu.dart';
import 'compact_layout.dart';
import '../logic/favorite_team.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import '../logic/strength_usage.dart';
import '../logic/strength_analytics.dart';
import 'team_section_layout.dart';
import 'strength_careers.dart' show careerGroupCard;
import 'compact_card_layout.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../config/app_design.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../logic/club_analysis.dart';
import '../tools/color_parse.dart';
import 'GamesBoard.dart' show teamLogoVisual, teamLogoImage;

const clubAnalysisGradeColors = <String, Color>{
  'S': Color(0xFFFFD700), 'A': Color(0xFFFF80AB),
  'B': Color(0xFFEF5350), 'C': Color(0xFFFF9800),
  'D': Color(0xFFFFEB3B), 'E': Color(0xFFB2DB59),
  'F': Color(0xFF81D4FA), 'G': Color(0xFFBDBDBD),
};

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
  String? _selectedStaff;
  final _staffHorizontal = ScrollController();

  @override
  void dispose() {
    _staffHorizontal.dispose();
    super.dispose();
  }
  int _teamSection = 0;
  static const _teamSections = ['📈分析', '🧠首脳陣', '😎主力選手', '🕊️貢献度', '👉選手起用', '📰選手一覧', '💼契約'];
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
      _selectedStaff = null;
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


  List<Map<String, dynamic>> get _clubs => listMapFromJson(_data['clubs']);
  String _analysisDetail(Map<String, dynamic> row, String category) {
    final method = row['defense_methods'][category];
    final value = row['metrics'][category];
    final evidence = ['内野守備', '外野守備'].contains(category) ? clubDefenseEvidence(row, category, widget.year) : null;
    return [
      '$category：${row['grades'][category]}（団体内の相対評価）',
      if (method == 'OAA') 'OAA：$value アウト（平均的な守備と比較したアウト獲得数）。打球の難易度・守備範囲を反映。送球による進塁抑止など守備の全要素を網羅する指標ではありません。',
      if (method == '失策参考') '守備率：${value == null ? '未計測' : (value as double).toStringAsFixed(4)}。この記号は失策の抑止のみの参考評価で、総合的な守備力ではありません。全チームで比較できる守備範囲データは未取得です。',
      if (method == null) '指標値：${value ?? '未計測'}',
      if (evidence != null) '対象：${evidence['year']}年／取得：${evidence['checked_at']}',
      if (row['defense_note'] is Map && row['defense_note']['category'] == category && '${row['defense_note']['year']}' == '${widget.year}')
        '${row['defense_note']['summary']}',
    ].join('\n\n');
  }

  Widget _analysisTeamCell(Map<String, dynamic> team, double height) {
    final background = parseColorNameOrNull('${team['color_back']}') ?? widget.org.tabColor;
    final foreground = parseColorNameOrNull('${team['color_font']}') ??
        (background.computeLuminance() > .45 ? Colors.black : Colors.white);
    final logo = teamLogoVisual('${team['name_team']}', abbrev: '${team['name_shortest'] ?? ''}', mlb: widget.org.kind == OrgKind.mlb);
    return Container(key: ValueKey('analysis-team-${team['id_team']}'),
      height: height, width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 8),
      color: background, child: compactBaseballLayout(context) ? Center(child: SizedBox(width: 60, height: 30, child: teamLogoImage(asset: logo.asset, networkUrl: logo.networkUrl, fallback: Text('${team['name_team']}', style: TextStyle(color: foreground, fontSize: 11))))) : Row(children: [
        SizedBox(width: 30, height: 30, child: teamLogoImage(asset: logo.asset, networkUrl: logo.networkUrl)),
        const SizedBox(width: 6),
        Expanded(child: Text('${team['name_team']}', style: TextStyle(color: foreground, fontWeight: FontWeight.bold))),
      ]));
  }

  Widget _analysis({Map<String, dynamic>? team, BuildContext? sectionContext}) {
    final rows = analyzeClubs(widget.teams, widget.year).where((row) => team == null || row['id_team'] == team['id_team']);
    final compact = compactBaseballLayout(context);
    const explanation = Padding(padding: EdgeInsets.all(8), child: Text('取得済み成績による団体内の相対評価（S → A → B → C → D → E → F → G）。打撃：打席加重OPS／走力：チームの(盗塁−2×盗塁死)÷消化試合数／守備：全比較球団の当年OAAが揃えばOAA。未取得の場合は内野・外野別の守備率を「失策参考」として表示／投手：主な起用が先発・救援の投手別WHIPを投球回で加重。中継ぎには抑えを含みます。走力は盗塁の参考評価で、進塁・走塁全体を網羅しません。守備機会は刺殺＋補殺＋失策。投手・捕手は内野守備に含めません。失策参考には守備範囲・ファインプレーを含めません。評価をクリックすると算出根拠を表示します。未計測は —。平均年齢は守備位置ごとの最多起用野手（重複除外）、当年は本日時点。'));
    final notes = <Widget>[
      for (final row in rows)
        if (row['defense_note'] is Map && '${row['defense_note']['year']}' == '${widget.year}')
          Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['name_team']}・守備評価の補足', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${row['defense_note']['summary']}'),
          ])),
    ];
    final children = <Widget>[
      LayoutBuilder(builder: (context, constraints) {
        final rowHeight = 88 * MediaQuery.textScalerOf(context).scale(12) / 12;
        Widget fitTable(Widget child) => team == null || compact ? child : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: child);
        final columns = [if (team == null) '球団', ...analysisCategories, 'レギュラー平均年齢', '強み', '弱み'];
        double weight(String c) => c == '球団' ? 2 : c == '強み' || c == '弱み' ? 2.4 : c == 'レギュラー平均年齢' ? 1.8 : 1;
        final table = DataTable(
            key: const ValueKey('analysis-table'),
            horizontalMargin: 0, columnSpacing: 0,
            headingRowHeight: team == null ? 0 : 56,
            headingRowColor: const WidgetStatePropertyAll(Colors.black),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            border: TableBorder.all(color: Colors.grey, width: .5),
            dataRowMinHeight: rowHeight, dataRowMaxHeight: rowHeight,
            columns: [
            for (final c in columns) DataColumn(columnWidth: compact && c == '球団' ? const FixedColumnWidth(46) : FlexColumnWidth(weight(c)), label: team == null ? const SizedBox.shrink() : Expanded(child: Text(c, textAlign: TextAlign.center)))
          ], rows: [
            for (final row in rows)
              DataRow(cells: [
                if (team == null) DataCell(_analysisTeamCell(row, rowHeight)),
                for (final c in analysisCategories)
                  DataCell(Center(child: Tooltip(
                    message: _analysisDetail(row, c),
                    child: InkWell(
                      onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
                        title: Text('${row['name_team']}・$c'),
                        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_analysisDetail(row, c)),
                        ])),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
                      )),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(key: ValueKey('analysis-grade-${row['id_team']}-$c'), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: clubAnalysisGradeColors[row['grades'][c]] ?? Colors.grey.shade200,
                            image: row['grades'][c] == 'S' ? const DecorationImage(
                              image: AssetImage('backend/assets/images/analysis_grade_gold.jpg'),
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(Color(0x99FFF2B0), BlendMode.screen),
                            ) : null,
                            border: Border.all(color: row['grades'][c] == 'S' ? const Color(0xFFE5B82E) : Colors.transparent),
                            borderRadius: BorderRadius.circular(4)),
                          child: Text('${row['grades'][c]}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
                        // Reserve the same caption line for every grade.
                        Text('${row['defense_methods'][c] ?? ' '}', maxLines: 1,
                          style: const TextStyle(fontSize: 10, height: 1.2)),
                      ]),
                    )))),
                DataCell(Center(child: Text(row['regular_age'] == null ? '—' : '${(row['regular_age'] as double).toStringAsFixed(1)}歳 (${row['age_count']}/${row['regular_count']}人)'))),
                DataCell(Padding(padding: const EdgeInsets.all(8), child: Text('${row['strengths']}'))),
                DataCell(Padding(padding: const EdgeInsets.all(8), child: Text('${row['weaknesses']}')))
              ])
          ]);
        if (compact && team != null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Table(key: const ValueKey('analysis-vertical-table'),
              columnWidths: const {0: FixedColumnWidth(100), 1: FlexColumnWidth()},
              border: TableBorder.all(color: Colors.grey, width: .5),
              defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
              children: [for (var i = 0; i < columns.length; i++) TableRow(children: [
                Container(key: ValueKey('analysis-header-${columns[i]}'), alignment: Alignment.centerLeft, padding: const EdgeInsets.all(8), color: Colors.black,
                  child: Text(columns[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                Padding(padding: const EdgeInsets.all(8), child: table.rows.first.cells[i].child),
              ])],
            ),
            explanation, ...notes,
          ]);
        }
        if (team == null) {
          final pinnedWidth = compact ? 46.0 : 180.0;
          final bodyWidth = math.max(1240.0, constraints.maxWidth) - pinnedWidth;
          final totalWeight = columns.skip(1).fold<double>(0, (n, c) => n + weight(c));
          return _PinnedAnalysisGrid(
            pinnedWidth: pinnedWidth, rowHeight: rowHeight,
            labels: columns.skip(1).toList(),
            widths: [for (final c in columns.skip(1)) bodyWidth * weight(c) / totalWeight],
            teamCells: [for (final row in table.rows) row.cells.first.child],
            cells: [for (final row in table.rows) [for (final cell in row.cells.skip(1)) cell.child]],
            footer: Column(children: [explanation, ...notes]),
          );
        }
        final width = math.max(1240.0, constraints.maxWidth);
        return sectionScrollView(context,
          key: const ValueKey('analysis-horizontal-scroll'),
          scrollDirection: Axis.horizontal,
          child: fitTable(SizedBox(width: width, child: table)));
      }),
      if (!compact && team != null) ...[explanation, ...notes],
    ];
    if (team != null) return SectionList(children: children);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: children.first),
    ]);
  }

  Widget _staff({Map<String, dynamic>? onlyClub, BuildContext? sectionContext}) {
    final clubs = onlyClub == null ? _clubs : [onlyClub];
    if (clubs.isEmpty) return const SizedBox.shrink();
    String clubKey(Map<String, dynamic> club) => '${club['code'] ?? club['name']}';
    final selected = clubs.firstWhere((club) => clubKey(club) == _selectedStaff, orElse: () => favoriteTeamRow(clubs) ?? clubs.first);
    final displayedClubs = [selected];
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
          Text('${p['role']}', style: const TextStyle(fontSize: 11)),
        ]),
      ]));
    return SectionList(children: [
      if (onlyClub == null) Padding(
        padding: const EdgeInsets.all(8),
        child: DropdownButton<String>(
          key: const ValueKey('staff-team-selector'),
          isExpanded: true,
          value: clubKey(selected),
          items: [for (final club in clubs) DropdownMenuItem(value: clubKey(club), child: Text('${club['name']}'))],
          onChanged: (value) => setState(() => _selectedStaff = value),
        ),
      ),
      const Padding(padding: EdgeInsets.all(8), child: Text('公式登録の軍・担当別。兼任は各担当列に表示。— は未収録。')),
      LayoutBuilder(builder: (context, constraints) {
        final compact = compactBaseballLayout(context);
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final pinnedWidth = (compact ? 28.0 : 52.0) * scale;
        final columnWidth = math.max(150.0 * scale, (constraints.maxWidth - pinnedWidth) / roles.length);
        final headerColor = Color.lerp(Colors.white, widget.org.tabColor, .15)!;
        Widget cell(Widget child, {bool header = false}) => Container(
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: header ? headerColor : null,
            border: Border.all(color: Colors.black26, width: .5)),
          child: child,
        );
        Widget row(String label, List<Widget> cells, {bool header = false}) => Stack(children: [
          ConstrainedBox(constraints: BoxConstraints(minHeight: (compact && !header ? 54 : 36) * scale),
            child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: pinnedWidth),
            for (final content in cells) SizedBox(width: columnWidth, child: cell(content, header: header)),
          ]))),
          Positioned(left: 0, top: 0, bottom: 0,
            child: AnimatedBuilder(
              animation: _staffHorizontal,
              builder: (context, child) => Transform.translate(
                offset: Offset(_staffHorizontal.hasClients ? _staffHorizontal.offset : 0, 0), child: child),
              child: SizedBox(width: pinnedWidth, child: cell(
                Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(compact ? label.split('').join('\n') : label,
                    key: ValueKey('staff-pinned-$label'), textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold)))), header: true)),
            )),
        ]);
        return SingleChildScrollView(
          key: const ValueKey('staff-horizontal-scroll'),
          controller: _staffHorizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: pinnedWidth + roles.length * columnWidth,
            child: Column(children: [
              row('軍', [for (final role in roles) Padding(padding: const EdgeInsets.all(8), child: Text(role))], header: true),
              for (final club in displayedClubs)
                for (var army = 1; army <= 4; army++) row('$army軍', [
                  for (final duty in roles) people(listMapFromJson(club['staff']).where((p) =>
                    !['オーナー','球団社長','スカウト'].contains(p['category']) && level(p) == army && duties(p).contains(duty))),
                ]),
            ])),
        );
      }),
      for (final club in displayedClubs) ...[
        Padding(padding: const EdgeInsets.all(8), child: Text('${club['name']}　オーナー・球団社長・スカウト')),
        people(listMapFromJson(club['staff']).where((p) => ['オーナー','球団社長','スカウト'].contains(p['category']))),
      ],
    ]);
  }

  Widget _training() {
    final groups = sortedTrainingGroups(_data['training_groups']);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = (constraints.maxWidth / 320).floor().clamp(1, 6);
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (groups.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('この年度の自主トレ情報はまだ収録されていません。')),
        CompactCardLayout(columns: columns, children: [
          for (final group in groups)
            careerGroupCard(context, {
              'name': group['name'],
              'players': [
                for (final member in listMapFromJson(group['members'])) {
                  'player': member,
                  'team': {
                    ...?widget.teams.where((team) =>
                      '${member['team'] ?? ''}'.isNotEmpty &&
                      ('${team['name_team']}' == '${member['team']}' ||
                       '${team['name_team']}'.contains('${member['team']}') ||
                       npbClubKey(team).isNotEmpty && npbClubKey(team) == npbClubKey({'name_team': member['team']}))).firstOrNull,
                    'name_team': member['team'] ?? '',
                  },
                  'career': {'detail': '${group['location'] ?? ''} ${group['period'] ?? ''}', 'source_url': group['source']},
                },
              ],
            }, width, category: '自主トレ',
              subtitle: Text('${group['location'] ?? ''} ${group['period'] ?? ''}', style: const TextStyle(fontSize: 11)),
            ),
        ]),
        Padding(padding: const EdgeInsets.all(8), child: Text('${widget.year}年シーズン前の自主トレ。公式発表・報道で確認できた参加者を人数順に表示しています。所属は当時の球団です。参加者は確認できた範囲です。')),
      ]));
    });
  }

  Widget _team() {
    if (widget.teams.isEmpty) return const Center(child: Text('戦力情報がありません'));
    final team = widget.teams.firstWhere((t) => '${t['id_team']}' == _selected, orElse: () => favoriteTeamRow(widget.teams) ?? widget.teams.first);
    final club = _clubs.where((c) => c['code'] == npbClubKey(team)).firstOrNull;
    final regularWidth = (pitcherAceSlots.length + usagePositions.length - 1) * 128.0;
    final background = parseColorNameOrNull('${team['color_back']}') ?? widget.org.tabColor;
    final foreground = parseColorNameOrNull('${team['color_font']}') ?? Colors.white;
    return LayoutBuilder(builder: (context, constraints) {
      Widget section(String title, Widget Function() builder, {double? minWidth, Key? key}) => _TeamSection(
        key: key,
        builder: () => minWidth == null ? builder() : SingleChildScrollView(
          key: ValueKey('team-section-horizontal-$title'), scrollDirection: Axis.horizontal,
          child: SizedBox(width: math.max(constraints.maxWidth, minWidth), child: builder())),
      );
      Widget usage(int index, String title, {double? minWidth}) => section(title,
        () => widget.teamSection(index, team), minWidth: minWidth, key: ValueKey('${team['id_team']}-$index'));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (NavigationPickerScope.enabled(context))
            NavigationPicker(level: 3, labels: {for (var i = 0; i < widget.teams.length; i++) i: '${widget.teams[i]['name_team'] ?? widget.teams[i]['name_shortest']}'},
              value: widget.teams.indexWhere((t) => t['id_team'] == team['id_team']),
              onChanged: (i) => setState(() => _selected = '${widget.teams[i]['id_team']}'), color: background, foreground: foreground)
          else
          MenuBand(level: 3, child: Padding(padding: const EdgeInsets.only(bottom: ALL_SPACE_BLOCK), child: LayoutBuilder(builder: (context, constraints) {
            final compact = compactBaseballLayout(context);
            final columns = compact ? widget.teams.length : (constraints.maxWidth / 100).floor().clamp(1, widget.teams.length);
            final segmentWidth = compact ? math.max(64.0, (constraints.maxWidth - (columns - 1) * ALL_SPACE_BLOCK) / columns) : (constraints.maxWidth - (columns - 1) * ALL_SPACE_BLOCK) / columns;
            Widget teamLabel(Map<String, dynamic> option) {
              final logo = teamLogoVisual('${option['name_team']}', abbrev: '${option['name_shortest'] ?? ''}', mlb: widget.org.kind == OrgKind.mlb);
              return Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 20, height: 20, child: teamLogoImage(asset: logo.asset, networkUrl: logo.networkUrl)),
                const SizedBox(width: 4),
                Text(compact ? '${option['name_shortest'] ?? option['name_team']}' : '${option['name_team']}', style: TextStyle(fontWeight: FontWeight.bold,
                  color: option['id_team'] == team['id_team']
                      ? parseColorNameOrNull('${option['color_font']}') ?? Colors.white : Colors.black87)),
              ]);
            }
            final segments = <Widget>[
              for (final option in widget.teams) SizedBox(width: segmentWidth,
                child: Semantics(button: true, selected: option['id_team'] == team['id_team'],
                  child: Material(
                    color: option['id_team'] == team['id_team']
                        ? parseColorNameOrNull('${option['color_back']}') ?? widget.org.tabColor : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      key: ValueKey('team-tab-segment-${option['id_team']}'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _selected = '${option['id_team']}'),
                      child: SizedBox(height: TAB_BAR_H, child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 8),
                        child: Center(child: FittedBox(fit: BoxFit.scaleDown,
                          child: teamLabel(option))),
                      )),
                    ),
                  ),
                ),
              ),
            ];
            if (compact) { return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final entry in segments.indexed) ...[
                if (entry.$1 > 0) const SizedBox(width: ALL_SPACE_BLOCK), entry.$2,
              ]]),
            );
            }
            return Wrap(spacing: ALL_SPACE_BLOCK, runSpacing: ALL_SPACE_BLOCK, children: segments);
          }))),
          if (NavigationPickerScope.enabled(context))
            NavigationPicker(level: 4, labels: {for (var i = 0; i < _teamSections.length; i++) i: _teamSections[i]}, value: _teamSection,
              onChanged: (i) => setState(() => _teamSection = i), color: background, foreground: foreground)
          else
          MenuBand(level: 4, child: Padding(
            padding: EdgeInsets.zero,
            child: SizedBox(height: TAB_BAR_H, child: Row(children: [
              for (var i = 0; i < _teamSections.length; i++) ...[
                if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
                Expanded(child: Semantics(
                  button: true, selected: _teamSection == i,
                  child: Material(
                    color: _teamSection == i ? background : Color.lerp(background, Colors.white, .9),
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                    child: InkWell(
                      key: ValueKey('team-section-segment-$i'),
                      borderRadius: BorderRadius.circular(TAB_RADIUS),
                      onTap: () => setState(() => _teamSection = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Center(child: FittedBox(fit: BoxFit.scaleDown,
                          child: Text(_teamSections[i], maxLines: 1, softWrap: false,
                            style: TextStyle(fontSize: 12, height: 1,
                              fontWeight: _teamSection == i ? FontWeight.bold : FontWeight.normal,
                              color: _teamSection == i ? foreground : Colors.black87)))),
                      ),
                    ),
                  ),
                )),
              ],
            ])),
          )),
          Expanded(child: SingleChildScrollView(
            key: ValueKey('team-page-vertical-scroll-${team['id_team']}-$_teamSection'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_teamSection == 0) section('分析', () => Builder(builder: (sectionContext) => _analysis(team: team, sectionContext: sectionContext)), minWidth: null),
          if (_teamSection == 1) section('首脳陣', () => club == null ? const Padding(padding: EdgeInsets.all(12), child: Text('この年度の首脳情報は未収録です。')) : Builder(builder: (sectionContext) => _staff(onlyClub: club, sectionContext: sectionContext)), minWidth: null),
          if (_teamSection == 2) usage(2, '主力選手', minWidth: compactBaseballLayout(context) ? null : regularWidth),
          if (_teamSection == 3) usage(0, '貢献度'),
          if (_teamSection == 4) usage(1, '選手起用'),
          if (_teamSection == 5) usage(3, '選手一覧'),
          if (_teamSection == 6) usage(4, '契約'),
          ]))),
        ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.view == 10) return _analysis();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_loading) const BaseballLoading(compact: true),
      if (_error != null) Row(children: [Expanded(child: Text(_error!)), TextButton(onPressed: _load, child: const Text('再読み込み'))]),
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
  const _TeamSection({super.key, required this.builder});
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) => TeamSectionLayout(child: builder());
}


class _PinnedAnalysisGrid extends StatefulWidget {
  const _PinnedAnalysisGrid({required this.pinnedWidth, required this.rowHeight,
    required this.labels, required this.widths, required this.teamCells,
    required this.cells, required this.footer});
  final double pinnedWidth, rowHeight;
  final List<String> labels;
  final List<double> widths;
  final List<Widget> teamCells;
  final List<List<Widget>> cells;
  final Widget footer;
  @override
  State<_PinnedAnalysisGrid> createState() => _PinnedAnalysisGridState();
}

class _PinnedAnalysisGridState extends State<_PinnedAnalysisGrid> {
  final _header = ScrollController(), _body = ScrollController();
  bool _syncing = false;
  @override
  void initState() {
    super.initState();
    _header.addListener(() => _sync(_header, _body));
    _body.addListener(() => _sync(_body, _header));
  }
  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _syncing = false;
  }
  @override
  void dispose() { _header.dispose(); _body.dispose(); super.dispose(); }
  Widget _cell(Widget child, double width, double height, {bool header = false}) =>
    Container(width: width, height: height, alignment: Alignment.center,
      decoration: BoxDecoration(color: header ? Colors.black : null,
        border: Border.all(color: Colors.grey, width: .5)), child: child);
  @override
  Widget build(BuildContext context) => Column(key: const ValueKey('analysis-table'), children: [
    Row(key: const ValueKey('analysis-fixed-header'), children: [
      _cell(const Text('球団', style: TextStyle(color: Colors.white)), widget.pinnedWidth, 56, header: true),
      Expanded(child: SingleChildScrollView(controller: _header,
        scrollDirection: Axis.horizontal, child: Row(children: [
          for (var i = 0; i < widget.labels.length; i++)
            _cell(Text(widget.labels[i], textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), widget.widths[i], 56, header: true),
        ]))),
    ]),
    Expanded(child: SingleChildScrollView(
      key: const ValueKey('analysis-vertical-scroll'),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(key: const ValueKey('analysis-pinned-teams'), children: [
            for (final cell in widget.teamCells) _cell(cell, widget.pinnedWidth, widget.rowHeight),
          ]),
          Expanded(child: SingleChildScrollView(controller: _body,
            key: const ValueKey('analysis-horizontal-scroll'),
            scrollDirection: Axis.horizontal, child: Column(children: [
              for (final row in widget.cells) Row(children: [
                for (var i = 0; i < row.length; i++) _cell(row[i], widget.widths[i], widget.rowHeight),
              ]),
            ]))),
        ]),
        widget.footer,
      ]))),
  ]);
}
