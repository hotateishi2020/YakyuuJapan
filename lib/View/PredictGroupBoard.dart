import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/org_config.dart';
import '../logic/predict_groups.dart';
import '../tools/color_parse.dart';

const predictSelectLabels = {
  'FREE': '自由選択',
  'DRAW': '被ったらくじ引き',
  'WAIVER': 'ウェーバー方式',
};

const predictPointLabels = {
  'SINGLE': '単勝1点方式',
  'TOP': '上位ポイント方式',
  'GAP': '順位ズレポイント方式',
};

/// 保存できたら null。失敗したら画面に出す文言。notice: で始まるときは案内。
typedef SavePredictSetting = Future<String?> Function(Map<String, dynamic> setting);
typedef ApprovePredictRule = Future<String?> Function(int settingId);
typedef RenamePredictGroup = Future<String?> Function(int id, String name);
typedef SearchPredictNames = Future<List<Map<String, dynamic>>> Function(String kind, int leagueId, String query);
typedef SearchPredictUsers = Future<List<Map<String, dynamic>>> Function(String query);
typedef CreatePredictGroup = Future<String?> Function(String name, List<int> userIds);
typedef AnswerPredictInvite = Future<String?> Function(int inviteId, bool accept);
typedef DeletePredictGroup = Future<String?> Function(int groupId);
typedef CreatePredictYear = Future<String?> Function(int groupId, int year);

String predictDisplayTitle(String title) => title == '優勝' ? '日本一' : title;

/// MLBタブの右にある予想タブ。
/// 上部は選んだ年の予想状況。グループ名の枠の中に年度を横並びで置く。
class PredictGroupBoard extends StatefulWidget {
  final bool loading;
  final String? error;
  final int selectedYear;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> titleCatalog;
  final int? viewerId;
  final SavePredictSetting? onSaveSetting;
  final ApprovePredictRule? onApproveRule;
  final RenamePredictGroup? onRenameGroup;
  final SearchPredictNames? onSearchNames;
  final List<Map<String, dynamic>> invites;
  final SearchPredictUsers? onSearchUsers;
  final CreatePredictGroup? onCreateGroup;
  final AnswerPredictInvite? onAnswerInvite;
  final DeletePredictGroup? onDeleteGroup;
  final CreatePredictYear? onCreateYear;

  const PredictGroupBoard({
    super.key,
    required this.loading,
    required this.groups,
    required this.selectedYear,
    this.titleCatalog = const [],
    this.viewerId,
    this.error,
    this.onSaveSetting,
    this.onApproveRule,
    this.onRenameGroup,
    this.onSearchNames,
    this.invites = const [],
    this.onSearchUsers,
    this.onCreateGroup,
    this.onAnswerInvite,
    this.onDeleteGroup,
    this.onCreateYear,
  });

  @override
  State<PredictGroupBoard> createState() => _PredictGroupBoardState();
}

class _PredictGroupBoardState extends State<PredictGroupBoard> {
  int? _focusGroup;
  int? _focusYear;

  @override
  void initState() {
    super.initState();
    _focusYear = widget.selectedYear;
  }

  @override
  void didUpdateWidget(covariant PredictGroupBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear) {
      _focusYear = widget.selectedYear;
      _focusGroup = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null && widget.groups.isEmpty) {
      return Center(child: Text(widget.error!));
    }
    final clusters = predictGroupClusters(widget.groups);
    if (clusters.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          _inviteList(),
          const SizedBox(height: 24),
          const Center(child: Text('予想グループはまだありません')),
          _addGroupButton(),
        ],
      );
    }
    final featured = _featured(clusters);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        _inviteList(),
        if (featured == null)
          _frame(
            header: '${_focusYear ?? widget.selectedYear}年の予想状況',
            large: true,
            child: const Text('この年の予想グループはありません', style: TextStyle(fontSize: 16)),
          )
        else
          _frame(
            header: '${featured.year == null ? '年度なし' : '${featured.year}年'}　${predictSeasonHeader(featured.year)}',
            large: true,
            child: _situation(featured.row, predictSeasonHeader(featured.year)),
          ),
        for (final cluster in clusters)
          _frame(
            header: cluster.name,
            onRename: () => _openRename(cluster.id, cluster.name),
            member: _isMember(cluster.years),
            onAddYear: () => _openYear(cluster.id, cluster.years),
            onDelete: () => _openDelete(cluster.id, cluster.name, _deleteApprovals(cluster.years)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_deleteApprovals(cluster.years).isNotEmpty) _deleteBanner(cluster.id, cluster.years),
                for (var i = 0; i < _visibleYears(cluster.years).length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  _yearRow(cluster.id, _visibleYears(cluster.years)[i], _userSlots(cluster.years)),
                ],
              ],
            ),
          ),
        _addGroupButton(),
      ],
    );
  }

  ({int? year, Map<String, dynamic> row})? _featured(List<({int id, String name, List<Map<String, dynamic>> years})> clusters) {
    final year = _focusYear;
    final groupId = _focusGroup;
    if (groupId != null) {
      for (final cluster in clusters) {
        if (cluster.id != groupId) continue;
        for (final row in cluster.years) {
          if (row['int_year'] == year) return (year: year, row: row);
        }
      }
    }
    for (final cluster in clusters) {
      for (final row in cluster.years) {
        if (row['int_year'] == year) return (year: year, row: row);
      }
    }
    final first = clusters.first.years;
    if (first.isEmpty) return null;
    return (year: first.first['int_year'] as int?, row: first.first);
  }

  int _userSlots(List<Map<String, dynamic>> years) {
    var slots = 1;
    for (final year in years) {
      final count = _maps(year['users']).length;
      if (count > slots) slots = count;
    }
    return slots;
  }

  Widget _yearRow(int groupId, Map<String, dynamic> yearRow, int slots) {
    final year = yearRow['int_year'] as int?;
    final selected = _focusGroup == groupId && _focusYear == year || (_focusGroup == null && _focusYear == year && _featuredGroup(groupId));
    final users = _maps(yearRow['users']);
    final userLine = users.isEmpty ? '参加 未登録' : '参加 ${users.map(_userName).join('・')}';
    const yearW = 48.0;
    const usersW = 150.0;
    const markW = 20.0;
    const hitW = 96.0;
    const editW = 36.0;
    final natural = yearW + usersW + markW + hitW * slots + editW;
    Widget row({required bool spacer}) {
      return Row(
        children: [
          SizedBox(
            width: yearW,
            child: Text(
              year == null ? '—' : '$year',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            width: usersW,
            child: Text(userLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(
            width: markW,
            child: Text('当', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          for (var i = 0; i < slots; i++)
            SizedBox(
              width: hitW,
              child: KeyedSubtree(
                key: ValueKey('predict-hit-$year-$i'),
                child: i < users.length ? _hitCell(users[i]) : const SizedBox.shrink(),
              ),
            ),
          if (spacer) const Spacer(),
          SizedBox(
            width: editW,
            height: 32,
            child: IconButton(
              tooltip: '予想設定',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: editW, minHeight: 32),
              onPressed: _asInt(yearRow['id_setting']) <= 0 ? null : () => _openEditor(year, yearRow),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
        ],
      );
    }

    return Material(
      color: selected ? const Color(0xFFE3F2FD) : Colors.white,
      child: InkWell(
        onTap: () => setState(() {
          _focusGroup = groupId;
          _focusYear = year;
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              if (!maxW.isFinite || maxW + 0.5 >= natural) return row(spacer: true);
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(width: natural, child: row(spacer: false)),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _hitCell(Map<String, dynamic> user) {
    return Row(
      children: [
        Flexible(
          child: Text(
            _userName(user),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 24,
          child: Text(
            '${_asInt(user['hits'])}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  bool _featuredGroup(int groupId) {
    final clusters = predictGroupClusters(widget.groups);
    for (final cluster in clusters) {
      if (cluster.years.any((row) => row['int_year'] == _focusYear)) return cluster.id == groupId;
    }
    return false;
  }

  Future<void> _openEditor(int? year, Map<String, dynamic> yearRow) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PredictSettingDialog(
        year: year,
        setting: yearRow,
        titleCatalog: widget.titleCatalog,
        viewerId: widget.viewerId,
        onSave: widget.onSaveSetting,
        onApprove: widget.onApproveRule,
        onSearch: widget.onSearchNames,
      ),
    );
  }

  Future<void> _openRename(int id, String name) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PredictNameDialog(
        groupId: id,
        name: name,
        onSave: widget.onRenameGroup,
      ),
    );
  }

  Widget _frame({
    required String header,
    required Widget child,
    bool large = false,
    VoidCallback? onRename,
    bool member = false,
    VoidCallback? onAddYear,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: large ? 14 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(large ? 10 : 8),
        border: Border.all(color: large ? const Color(0xFF37474F) : const Color(0xFFD0D0D6), width: large ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF37474F),
            padding: EdgeInsets.fromLTRB(large ? 14 : 12, large ? 8 : 2, 4, large ? 8 : 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: TextStyle(color: Colors.white, fontSize: large ? 18 : 15, fontWeight: FontWeight.bold),
                  ),
                ),
                if (member && onAddYear != null)
                  IconButton(
                    tooltip: '年度を追加',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: onAddYear,
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                if (onRename != null)
                  IconButton(
                    tooltip: 'グループ名を編集',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: onRename,
                    icon: const Icon(Icons.drive_file_rename_outline, color: Colors.white, size: 18),
                  ),
                if (member && onDelete != null)
                  IconButton(
                    tooltip: 'グループを削除',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                  ),
              ],
            ),
          ),
          if (large)
            Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 14), child: child)
          else
            child,
        ],
      ),
    );
  }

  Widget _situation(Map<String, dynamic> group, String resultHeader) {
    final users = _maps(group['users']);
    final teams = _maps(group['teams']);
    final players = _maps(group['players']);
    final champions = _maps(group['champions']);
    final japan = group['japan'] is Map ? Map<String, dynamic>.from(group['japan'] as Map) : null;
    final sawamura = players.where((row) => '${row['title'] ?? ''}' == '沢村賞').toList();
    final leaguePlayers = [for (final row in players) if ('${row['title'] ?? ''}' != '沢村賞') row];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _waiverNotice(group),
        Text(_name(group), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (users.isEmpty)
          const Text('参加ユーザーはまだいません', style: TextStyle(fontSize: 15))
        else
          Row(
            children: [
              for (final user in users)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _userColor(user).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _userColor(user).withValues(alpha: 0.45)),
                      ),
                      child: Column(
                        children: [
                          Text(_userName(user), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _userColor(user))),
                          const SizedBox(height: 2),
                          Text('${_asInt(user['hits'])}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.05)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (teams.isNotEmpty || champions.isNotEmpty || sawamura.isNotEmpty)
          _area(
            title: 'チーム順位予想',
            color: const Color(0xFFE3F2FD),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                predictJapanBanner(),
                const SizedBox(height: 4),
                _pickTable(
                  users: users,
                  rows: [
                    {
                      'title': '日本一',
                      'current': '${japan?['name'] ?? ''}'.trim(),
                      'color_back': '${japan?['color_back'] ?? ''}',
                      'color_font': '${japan?['color_font'] ?? ''}',
                      'picks': [
                        for (final row in champions) {'id_user': row['id_user'], 'name': row['name'], 'hit': row['hit'] == true},
                      ],
                    },
                    for (final row in sawamura) row,
                  ],
                  resultHeader: resultHeader,
                  titleOf: (row) => '${row['title'] ?? '日本一'}',
                  titleColor: (row) => '${row['title'] ?? ''}' == '沢村賞' ? const Color(0xFF1565C0) : null,
                  centerOf: (row) {
                    final current = '${row['current'] ?? ''}'.trim();
                    return current.isEmpty ? '—' : current;
                  },
                ),
                if (teams.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _leagueSections(
                    users: users,
                    rows: teams,
                    resultHeader: resultHeader,
                    titleOf: (row) => '${_asInt(row['rank'])}位',
                    centerOf: (row) => '${row['actual'] ?? ''}'.trim().isEmpty ? '—' : '${row['actual']}',
                  ),
                ],
              ],
            ),
          ),
        if (leaguePlayers.isNotEmpty)
          _area(
            title: '個人成績予想',
            color: const Color(0xFFFFF3E0),
            child: _leagueSections(
              users: users,
              rows: leaguePlayers,
              resultHeader: resultHeader,
              titleOf: (row) => '${row['title'] ?? ''}',
              centerOf: (row) => '${row['current'] ?? ''}'.trim().isEmpty ? '—' : '${row['current']}',
              titleColor: (row) => row['pitcher'] == true ? const Color(0xFF1E88E5) : const Color(0xFFDC143C),
            ),
          ),
      ],
    );
  }

  Widget _area({required String title, required Color color, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _leagueSections({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> rows,
    required String resultHeader,
    required String Function(Map<String, dynamic> row) titleOf,
    required String Function(Map<String, dynamic> row) centerOf,
    Color? Function(Map<String, dynamic> row)? titleColor,
  }) {
    final order = <String>[];
    for (final row in rows) {
      final label = _leagueLabel(row);
      if (!order.contains(label)) order.add(label);
    }
    order.sort((a, b) => _leagueSort(a).compareTo(_leagueSort(b)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < order.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _leagueBanner(order[i]),
          const SizedBox(height: 4),
          _pickTable(
            users: users,
            rows: _mvpFirst([for (final row in rows) if (_leagueLabel(row) == order[i]) row]),
            resultHeader: resultHeader,
            titleOf: titleOf,
            centerOf: centerOf,
            titleColor: titleColor,
          ),
        ],
      ],
    );
  }

  String _leagueLabel(Map<String, dynamic> row) {
    final league = '${row['league'] ?? ''}'.trim();
    return league.isEmpty ? 'リーグなし' : league;
  }

  int _leagueSort(String name) {
    if (name.contains('セ')) return 0;
    if (name.contains('パ')) return 1;
    return 2;
  }

  List<Map<String, dynamic>> _mvpFirst(List<Map<String, dynamic>> rows) {
    final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
    indexed.sort((a, b) {
      final am = '${a.$2['title'] ?? ''}' == 'MVP' ? 0 : 1;
      final bm = '${b.$2['title'] ?? ''}' == 'MVP' ? 0 : 1;
      if (am != bm) return am.compareTo(bm);
      return a.$1.compareTo(b.$1);
    });
    return [for (final row in indexed) row.$2];
  }

  Color? _teamPaint(dynamic name) => parseColorNameOrNull('${name ?? ''}');

  bool _tiedLeaders(Map<String, dynamic> row) {
    final current = '${row['current'] ?? ''}'.trim();
    return current.contains('、');
  }

  Color? _resultBack(Map<String, dynamic> row) {
    if (_tiedLeaders(row)) return Colors.white;
    return _teamPaint(row['color_back']);
  }

  Color? _resultFont(Map<String, dynamic> row) {
    if (_tiedLeaders(row)) return Colors.black;
    return _teamPaint(row['color_font']);
  }

  Widget _waiverNotice(Map<String, dynamic> group) {
    final waiver = group['waiver'];
    if (waiver is! Map || waiver['active'] != true) return const SizedBox.shrink();
    final next = '${waiver['turn_name'] ?? ''}'.trim();
    final user = '${waiver['last_user'] ?? ''}'.trim();
    final team = '${waiver['last_team'] ?? ''}'.trim();
    final player = '${waiver['last_player'] ?? ''}'.trim();
    final title = '${waiver['last_title'] ?? ''}'.trim();
    final text = user.isEmpty || player.isEmpty
        ? '次は$nextが予想タイトルを選択する順番です。'
        : '$userが${team.isEmpty ? '' : '$teamの'}$playerを$title首位と予想しました、次は$nextが予想タイトルを選択する順番です。';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.35)),
    );
  }

  Widget _leagueBanner(String name) {
    return predictLeagueBanner(name);
  }

  List<Map<String, dynamic>> _visibleYears(List<Map<String, dynamic>> years) {
    return [for (final year in years) if (_asInt(year['id_setting']) > 0) year];
  }

  bool _isMember(List<Map<String, dynamic>> years) {
    final id = widget.viewerId;
    if (id == null || id <= 0) return false;
    for (final year in years) {
      for (final user in _maps(year['users'])) {
        if (_asInt(user['id']) == id) return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _deleteApprovals(List<Map<String, dynamic>> years) {
    for (final year in years) {
      final rows = _maps(year['delete_approvals']);
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  Widget _addGroupButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _openCreateGroup,
        icon: const Icon(Icons.group_add_outlined, size: 18),
        label: const Text('グループを追加'),
      ),
    );
  }

  Widget _inviteList() {
    if (widget.invites.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final invite in widget.invites)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${invite['from_name'] ?? ''}さんから「${invite['txt_name'] ?? ''}」への招待が来ています',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(onPressed: () => _answerInvite(invite, false), child: const Text('辞退')),
                TextButton(onPressed: () => _answerInvite(invite, true), child: const Text('参加する')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _deleteBanner(int groupId, List<Map<String, dynamic>> years) {
    final approvals = _deleteApprovals(years);
    final members = <int>{};
    for (final year in years) {
      for (final user in _maps(year['users'])) {
        final id = _asInt(user['id']);
        if (id > 0) members.add(id);
      }
    }
    final agreed = approvals.map((row) => _asInt(row['id_user'])).toSet();
    final waiting = <String>[];
    for (final year in years) {
      for (final user in _maps(year['users'])) {
        final id = _asInt(user['id']);
        if (id > 0 && !agreed.contains(id) && !waiting.contains(_userName(user))) waiting.add(_userName(user));
      }
    }
    final mine = widget.viewerId;
    final already = mine != null && agreed.contains(mine);
    return Container(
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '削除の提案 ${agreed.length}/${members.length}人がOK${waiting.isEmpty ? '' : '　未OK: ${waiting.join('、')}'}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (!already && _isMember(years))
            TextButton(onPressed: () => _confirmDelete(groupId), child: const Text('OKする')),
        ],
      ),
    );
  }

  Future<void> _openCreateGroup() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PredictGroupCreateDialog(
        onSearch: widget.onSearchUsers,
        onCreate: widget.onCreateGroup,
      ),
    );
  }

  Future<void> _openYear(int groupId, List<Map<String, dynamic>> years) async {
    final taken = <int>{
      for (final year in years)
        if (year['int_year'] is int) year['int_year'] as int,
    };
    await showDialog<void>(
      context: context,
      builder: (context) => _PredictYearDialog(
        groupId: groupId,
        taken: taken,
        onCreate: widget.onCreateYear,
      ),
    );
  }

  Future<void> _openDelete(int groupId, String name, List<Map<String, dynamic>> approvals) async {
    final already = widget.viewerId != null && approvals.any((row) => _asInt(row['id_user']) == widget.viewerId);
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('すでにOKしています')));
      return;
    }
    await _confirmDelete(groupId, name: name);
  }

  Future<void> _confirmDelete(int groupId, {String? name}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループを削除'),
        content: Text('${name == null ? 'このグループ' : '「$name」'}の削除には、参加ユーザー全員のOKが必要です。OKしますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('OKする')),
        ],
      ),
    );
    if (ok != true || widget.onDeleteGroup == null) return;
    final error = await widget.onDeleteGroup!(groupId);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _answerInvite(Map<String, dynamic> invite, bool accept) async {
    if (widget.onAnswerInvite == null) return;
    final error = await widget.onAnswerInvite!(_asInt(invite['id']), accept);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Widget _pickTable({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic> row) titleOf,
    required String resultHeader,
    required String Function(Map<String, dynamic> row) centerOf,
    Color? Function(Map<String, dynamic> row)? titleColor,
  }) {
    const gridLine = Color(0xFFD0D0D6);
    Widget cell(String text, {bool hit = false, Color? color, FontWeight weight = FontWeight.w600, Color? background, bool names = false}) {
      final style = TextStyle(fontSize: 13, fontWeight: weight, color: color ?? Colors.black87, height: 1.2);
      return TableCell(
        verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          alignment: Alignment.center,
          color: hit ? const Color(0xFFFFCC00) : (background ?? const Color(0xFFFFF3C4)),
          child: names ? _fitNames(text, style) : Text(text.isEmpty ? '—' : text, textAlign: TextAlign.center, style: style),
        ),
      );
    }

    String pickName(Map<String, dynamic> row, Map<String, dynamic> user) {
      final picks = _maps(row['picks']);
      for (final pick in picks) {
        if (_asInt(pick['id_user']) == _asInt(user['id'])) return '${pick['name'] ?? ''}';
      }
      return '';
    }

    bool pickHit(Map<String, dynamic> row, Map<String, dynamic> user) {
      final picks = _maps(row['picks']);
      for (final pick in picks) {
        if (_asInt(pick['id_user']) == _asInt(user['id'])) return pick['hit'] == true;
      }
      return false;
    }

    TableRow line(List<Widget> cells, {Color? background}) {
      return TableRow(
        decoration: BoxDecoration(color: background ?? const Color(0xFFFFF3C4)),
        children: cells,
      );
    }

    return Table(
      border: TableBorder.all(color: gridLine, width: 1),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FlexColumnWidth(3),
        1: const FlexColumnWidth(2),
        for (var i = 0; i < users.length; i++) i + 2: const FlexColumnWidth(2),
      },
      children: [
        line(
          [
            cell('', weight: FontWeight.bold, background: const Color(0xFFF7F7F7)),
            cell(resultHeader, weight: FontWeight.bold, background: const Color(0xFFF7F7F7)),
            for (final user in users) cell(_userName(user), weight: FontWeight.bold, color: _userColor(user), background: const Color(0xFFF7F7F7)),
          ],
          background: const Color(0xFFF7F7F7),
        ),
        for (final row in rows)
          line([
            cell(titleOf(row), weight: FontWeight.bold, color: titleColor?.call(row)),
            cell(
              centerOf(row),
              background: _resultBack(row),
              color: _resultFont(row),
              names: true,
            ),
            for (final user in users) cell(pickName(row, user), hit: pickHit(row, user), names: true),
          ]),
      ],
    );
  }

  static String _name(Map<String, dynamic> group) {
    final name = '${group['txt_name'] ?? ''}'.trim();
    return name.isEmpty ? '名称未設定' : name;
  }

  String _userName(Map<String, dynamic> user) {
    final name = '${user['name'] ?? ''}'.trim();
    return name.isEmpty ? 'ユーザー${_asInt(user['id'])}' : name;
  }

  Color _userColor(Map<String, dynamic> user) {
    return parseColorNameOrNull('${user['color'] ?? ''}') ?? const Color(0xFF37474F);
  }
}

List<String> _nameLines(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const ['—'];
  if (!trimmed.contains('、')) return [trimmed];
  final parts = [for (final part in trimmed.split('、')) part.trim()].where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? const ['—'] : parts;
}

Widget _fitLine(String text, TextStyle style) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.center,
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: style,
    ),
  );
}

Widget _fitNames(String text, TextStyle style) {
  final lines = _nameLines(text);
  if (lines.length == 1) return _fitLine(lines.single, style);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [for (final line in lines) _fitLine(line, style)],
  );
}

class _TitleDraft {
  int? idStats;
  String title;
  bool? pitcher;

  _TitleDraft({required this.title, this.idStats, this.pitcher});
}

class _EditSlot {
  _EditSlot(String value)
      : confirmed = value,
        controller = TextEditingController(text: value);

  final TextEditingController controller;
  String confirmed;
  bool editing = false;
  List<Map<String, dynamic>> suggestions = const [];
  int searchGen = 0;
}

const _predictLeagues = [
  (id: 1, name: 'セ・リーグ'),
  (id: 2, name: 'パ・リーグ'),
];

const _specialPredictTitles = {'チーム順位', '優勝', '日本一'};

const _fallbackPredictTitles = ['打率', '本塁打', '打点', '盗塁', '出塁率', '防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'MVP', '沢村賞'];

class _PredictSettingDialog extends StatefulWidget {
  final int? year;
  final Map<String, dynamic> setting;
  final List<Map<String, dynamic>> titleCatalog;
  final int? viewerId;
  final SavePredictSetting? onSave;
  final ApprovePredictRule? onApprove;
  final SearchPredictNames? onSearch;

  const _PredictSettingDialog({
    required this.year,
    required this.setting,
    required this.titleCatalog,
    required this.viewerId,
    required this.onSave,
    required this.onApprove,
    required this.onSearch,
  });

  @override
  State<_PredictSettingDialog> createState() => _PredictSettingDialogState();
}

class _PredictSettingDialogState extends State<_PredictSettingDialog> {
  late final TextEditingController _limitTeam;
  late final TextEditingController _limitPlayer;
  late final TextEditingController _same;
  late String _select;
  late String _point;
  late final List<_TitleDraft> _titles;
  final Map<String, _EditSlot> _slots = {};
  final List<TextEditingController> _retiredSlots = [];
  String? _error;
  String? _notice;
  bool _saving = false;
  Map<String, dynamic>? _proposal;
  final Set<String> _waiverSeed = {};
  String? _waiverPick;

  @override
  void initState() {
    super.initState();
    _limitTeam = TextEditingController(text: _initialDate('date_limit_team'));
    _limitPlayer = TextEditingController(text: _initialDate('date_limit_player'));
    final proposal = widget.setting['proposal'];
    if (proposal is Map) _proposal = Map<String, dynamic>.from(proposal);
    _same = TextEditingController(text: '${_asInt(widget.setting['int_same_player_limit']) == 0 ? 1 : _asInt(widget.setting['int_same_player_limit'])}');
    _select = predictSelectLabels.containsKey('${widget.setting['code_select']}') ? '${widget.setting['code_select']}' : 'FREE';
    _point = predictPointLabels.containsKey('${widget.setting['code_point']}') ? '${widget.setting['code_point']}' : 'SINGLE';
    _titles = _readTitles();
    _fillSlots();
  }

  @override
  void dispose() {
    _limitTeam.dispose();
    _limitPlayer.dispose();
    _same.dispose();
    for (final slot in _slots.values) {
      slot.controller.dispose();
    }
    for (final controller in _retiredSlots) {
      controller.dispose();
    }
    super.dispose();
  }

  String _dateOnly(String raw) {
    final text = raw.trim();
    if (text.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text.substring(0, 10))) return text.substring(0, 10);
    return '';
  }

  String _initialDate(String key) {
    if (widget.setting.containsKey(key)) return _dateOnly('${widget.setting[key] ?? ''}');
    return _dateOnly('${widget.setting['date_limit'] ?? ''}');
  }

  bool get _teamClosed => predictDeadlinePassed(_initialDate('date_limit_team'));
  bool get _playerClosed => predictDeadlinePassed(_initialDate('date_limit_player'));

  int _ownerOf(String key) => int.tryParse(key.split('|').last) ?? 0;

  bool get _waiverActive {
    final waiver = widget.setting['waiver'];
    return waiver is Map && waiver['active'] == true;
  }

  bool _slotOpen(String key, String kind) {
    final closed = kind == 'player' ? _playerClosed : _teamClosed;
    if (!predictCanEditSlot(viewerId: widget.viewerId, ownerId: _ownerOf(key), closed: closed)) return false;
    if (kind != 'player' || !_waiverActive) return true;
    final waiver = widget.setting['waiver'];
    final turn = waiver is Map ? _asInt(waiver['turn_user']) : 0;
    if (widget.viewerId != turn) return false;
    if (_waiverSeed.contains(key)) return false;
    if (_waiverPick != null && _waiverPick != key) return false;
    return true;
  }

  List<_TitleDraft> _readTitles() {
    final raw = widget.setting['titles'];
    if (raw is! List) return [];
    final titles = <_TitleDraft>[];
    for (final item in raw) {
      if (item is String) {
        final title = item.trim();
        if (title.isNotEmpty) titles.add(_TitleDraft(title: title, pitcher: _pitcherOf(title, null)));
        continue;
      }
      if (item is! Map) continue;
      final title = '${item['txt_title'] ?? item['title'] ?? ''}'.trim();
      if (title.isEmpty) continue;
      final stats = int.tryParse('${item['id_stats'] ?? ''}');
      final rawPitcher = item['pitcher'];
      titles.add(_TitleDraft(
        title: title,
        idStats: stats == null || stats <= 0 ? null : stats,
        pitcher: _pitcherOf(title, rawPitcher == true ? true : rawPitcher == false ? false : null),
      ));
    }
    return titles;
  }

  bool? _pitcherOf(String title, bool? known) {
    if (_specialPredictTitles.contains(title)) return null;
    if (known != null) return known;
    if (_pitchingTitles.contains(title)) return true;
    if (_battingTitles.contains(title)) return false;
    return null;
  }

  _EditSlot _slot(String key, [String initial = '']) {
    return _slots.putIfAbsent(key, () => _EditSlot(initial));
  }

  void _fillSlots() {
    for (final user in _users) {
      final userId = _asInt(user['id']);
      if (userId <= 0) continue;
      _slot('c|$userId');
      for (final league in _predictLeagues) {
        for (var rank = 1; rank <= 6; rank++) {
          _slot('r|${league.id}|$rank|$userId');
        }
      }
    }
    for (final title in _titles) {
      _ensurePlayerSlots(title.title);
    }
    final players = widget.setting['players'];
    if (players is List) {
      for (final row in players) {
        if (row is! Map) continue;
        final title = '${row['title'] ?? ''}'.trim();
        final leagueName = '${row['league'] ?? ''}';
        final leagueId = int.tryParse('${row['id_league'] ?? ''}') ?? (leagueName.contains('パ') ? 2 : leagueName.contains('セ') ? 1 : 0);
        final picks = row['picks'];
        if (title.isEmpty || picks is! List) continue;
        if (leagueId == 0 && title != '沢村賞') continue;
        for (final pick in picks) {
          if (pick is! Map) continue;
          final userId = int.tryParse('${pick['id_user']}') ?? 0;
          if (userId <= 0) continue;
          final key = _playerKey(title, leagueId, userId);
          final slot = _slot(key);
          slot.confirmed = '${pick['name'] ?? ''}';
          slot.controller.text = slot.confirmed;
          if (slot.confirmed.trim().isNotEmpty) _waiverSeed.add(key);
        }
      }
    }
    final teams = widget.setting['teams'];
    if (teams is List) {
      for (final row in teams) {
        if (row is! Map) continue;
        final leagueName = '${row['league'] ?? ''}';
        final leagueId = int.tryParse('${row['id_league'] ?? ''}') ?? (leagueName.contains('パ') ? 2 : leagueName.contains('セ') ? 1 : 0);
        final rank = int.tryParse('${row['rank'] ?? ''}') ?? 0;
        final picks = row['picks'];
        if (leagueId == 0 || rank < 1 || picks is! List) continue;
        for (final pick in picks) {
          if (pick is! Map) continue;
          final userId = int.tryParse('${pick['id_user']}') ?? 0;
          if (userId <= 0) continue;
          final slot = _slot('r|$leagueId|$rank|$userId');
          slot.confirmed = '${pick['name'] ?? ''}';
          slot.controller.text = slot.confirmed;
        }
      }
    }
    final champions = widget.setting['champions'];
    if (champions is List) {
      for (final row in champions) {
        if (row is! Map) continue;
        final userId = int.tryParse('${row['id_user']}') ?? 0;
        if (userId <= 0) continue;
        final slot = _slot('c|$userId');
        slot.confirmed = '${row['name'] ?? ''}';
        slot.controller.text = slot.confirmed;
      }
    }
  }

  List<Map<String, dynamic>> get _users => _maps(widget.setting['users']);

  List<({int? id, String title, bool? pitcher})> get _catalog {
    final seen = <String>{};
    final items = <({int? id, String title, bool? pitcher})>[];
    for (final row in widget.titleCatalog) {
      final title = '${row['title'] ?? ''}'.trim();
      if (title.isEmpty || !seen.add(title)) continue;
      final id = int.tryParse('${row['id'] ?? ''}');
      final pitcher = row['pitcher'] == true ? true : row['pitcher'] == false ? false : _pitcherOf(title, null);
      items.add((id: id == null || id <= 0 ? null : id, title: title, pitcher: pitcher));
    }
    for (final title in _fallbackPredictTitles) {
      if (seen.add(title)) items.add((id: null, title: title, pitcher: _pitcherOf(title, null)));
    }
    return items;
  }

  String _playerKey(String title, int leagueId, int userId) => 'p|$title|$leagueId|$userId';

  void _ensurePlayerSlots(String title) {
    if (_specialPredictTitles.contains(title)) return;
    if (title == '沢村賞') {
      for (final user in _users) {
        final userId = _asInt(user['id']);
        if (userId <= 0) continue;
        _slot(_playerKey(title, 0, userId));
      }
      return;
    }
    for (final league in _predictLeagues) {
      for (final user in _users) {
        final userId = _asInt(user['id']);
        if (userId <= 0) continue;
        _slot(_playerKey(title, league.id, userId));
      }
    }
  }

  void _addTitle(String title, {int? idStats, bool? pitcher}) {
    if (_titles.any((item) => item.title == title)) return;
    final known = _catalog.where((item) => item.title == title);
    _titles.add(_TitleDraft(
      title: title,
      idStats: idStats ?? (known.isEmpty ? null : known.first.id),
      pitcher: pitcher ?? (known.isEmpty ? _pitcherOf(title, null) : known.first.pitcher),
    ));
    _ensurePlayerSlots(title);
  }

  void _removeTitle(_TitleDraft draft) {
    _titles.remove(draft);
    final marker = '|${draft.title}|';
    final keys = _slots.keys.where((key) => key.startsWith('p|') && key.contains(marker)).toList();
    for (final key in keys) {
      final slot = _slots.remove(key);
      if (slot != null) _retiredSlots.add(slot.controller);
    }
  }

  Future<void> _save() async {
    final teamLimit = _dateOnly(_limitTeam.text);
    final playerLimit = _dateOnly(_limitPlayer.text);
    if ((_limitTeam.text.trim().isNotEmpty && teamLimit.isEmpty) || (_limitPlayer.text.trim().isNotEmpty && playerLimit.isEmpty)) {
      setState(() => _error = '期限の日付が不正です');
      return;
    }
    final same = int.tryParse(_same.text.trim());
    if (same == null || same < 1) {
      setState(() => _error = '同一選手の上限は1以上にしてください');
      return;
    }
    if (_slots.values.any((slot) => slot.editing)) {
      setState(() => _error = '入力中の項目を確定するか中止してください');
      return;
    }
    final mine = widget.viewerId;
    final picks = <Map<String, dynamic>>[];
    final ranks = <Map<String, dynamic>>[];
    final champions = <Map<String, dynamic>>[];
    if (mine != null && mine > 0 && !_playerClosed) {
      for (final title in _titles) {
        if (_specialPredictTitles.contains(title.title)) continue;
        if (title.title == '沢村賞') {
          picks.add({
            'id_user': mine,
            'id_league': 0,
            'id_stats': title.idStats,
            'txt_title': title.title,
            'name': _slots[_playerKey(title.title, 0, mine)]?.confirmed.trim() ?? '',
          });
          continue;
        }
        for (final league in _predictLeagues) {
          picks.add({
            'id_user': mine,
            'id_league': league.id,
            'id_stats': title.idStats,
            'txt_title': title.title,
            'name': _slots[_playerKey(title.title, league.id, mine)]?.confirmed.trim() ?? '',
          });
        }
      }
    }
    if (mine != null && mine > 0 && !_teamClosed) {
      for (final league in _predictLeagues) {
        for (var rank = 1; rank <= 6; rank++) {
          ranks.add({
            'id_user': mine,
            'id_league': league.id,
            'rank': rank,
            'name': _slots['r|${league.id}|$rank|$mine']?.confirmed.trim() ?? '',
          });
        }
      }
      champions.add({
        'id_user': mine,
        'name': _slots['c|$mine']?.confirmed.trim() ?? '',
      });
    }
    final draft = {
      'id_setting': _asInt(widget.setting['id_setting']),
      'date_limit_team': teamLimit,
      'date_limit_player': playerLimit,
      'code_select': _select,
      'int_same_player_limit': same,
      'code_point': _point,
      'titles': [
        for (final title in _titles) {'id_stats': title.idStats, 'txt_title': title.title},
      ],
      if (mine != null && mine > 0 && !_playerClosed) 'picks': picks,
      if (mine != null && mine > 0 && !_teamClosed) 'ranks': ranks,
      if (mine != null && mine > 0 && !_teamClosed) 'champions': champions,
    };
    if (widget.onSave == null) {
      setState(() => _error = '保存できませんでした');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave!(draft);
    if (!mounted) return;
    if (error != null && error.startsWith('notice:')) {
      final mine = widget.viewerId;
      setState(() {
        _saving = false;
        _error = null;
        _notice = error.substring(7);
        _proposal = {
          'proposer_id': mine,
          'proposer_name': _viewerName(mine),
          'date_limit_team': teamLimit,
          'date_limit_player': playerLimit,
          'code_select': _select,
          'int_same_player_limit': same,
          'code_point': _point,
          'approvals': [
            {'id_user': mine, 'name': ''},
          ],
        };
      });
      return;
    }
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _vote() async {
    if (widget.onApprove == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final message = await widget.onApprove!(_asInt(widget.setting['id_setting']));
    if (!mounted) return;
    if (message == 'notice:applied') {
      final proposal = _proposal;
      setState(() {
        _saving = false;
        _notice = '全員が賛成したので、期限とルールを反映しました';
        _error = null;
        if (proposal != null) {
          _limitTeam.text = _dateOnly('${proposal['date_limit_team'] ?? ''}');
          _limitPlayer.text = _dateOnly('${proposal['date_limit_player'] ?? ''}');
          final select = '${proposal['code_select'] ?? ''}';
          final point = '${proposal['code_point'] ?? ''}';
          if (predictSelectLabels.containsKey(select)) _select = select;
          if (predictPointLabels.containsKey(point)) _point = point;
          final same = _asInt(proposal['int_same_player_limit']);
          if (same > 0) _same.text = '$same';
        }
        _proposal = null;
      });
      return;
    }
    if (message == 'notice:pending') {
      final mine = widget.viewerId;
      final proposal = _proposal ?? <String, dynamic>{};
      final approvals = [
        for (final row in (proposal['approvals'] is List ? proposal['approvals'] as List : const []))
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      if (!approvals.any((row) => _asInt(row['id_user']) == mine)) {
        approvals.add({'id_user': mine, 'name': ''});
      }
      proposal['approvals'] = approvals;
      setState(() {
        _saving = false;
        _proposal = proposal;
        _notice = '賛成しました。全員の賛成後に反映されます';
        _error = null;
      });
      return;
    }
    setState(() {
      _saving = false;
      _error = message ?? '賛成を保存できませんでした';
    });
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final year = widget.year ?? DateTime.now().year;
    final marks = widget.setting['season_marks'];
    final picked = await pickPredictDeadline(
      context,
      year,
      marks: marks is Map ? Map<String, dynamic>.from(marks) : null,
      current: controller.text,
    );
    if (picked == null || !mounted) return;
    setState(() => controller.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final yearLabel = widget.year == null ? '年度なし' : '${widget.year}年';
    final available = [for (final item in _catalog) if (!_titles.any((title) => title.title == item.title)) item];
    final playerTitles = [
      for (final title in _titles)
        if (!_specialPredictTitles.contains(title.title) && title.title != '沢村賞' && title.title != 'MVP') title,
    ];
    final mvpTitles = [for (final title in _titles) if (title.title == 'MVP') title];
    final orderedPlayerTitles = [...mvpTitles, ...playerTitles];
    return AlertDialog(
      title: Text('$yearLabelの予想設定'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dateButton('チーム順位の予想期限', _limitTeam),
              const SizedBox(height: 8),
              _dateButton('個人成績予想の期限', _limitPlayer),
              const SizedBox(height: 8),
              const Text(
                '期限とルール（選手選択形式・同一選手選択上限・ポイント計算方式）の変更は、保存すると変更案になります。参加ユーザー全員が賛成すると反映されます。',
                style: TextStyle(fontSize: 12, color: Color(0xFF546E7A)),
              ),
              if (_proposal != null) ...[
                const SizedBox(height: 8),
                _proposalBox(),
              ],
              const SizedBox(height: 12),
              const Text('選手選択形式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                isExpanded: true,
                value: _select,
                items: [
                  for (final entry in predictSelectLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _saving ? null : (value) => setState(() => _select = value ?? _select),
              ),
              const SizedBox(height: 8),
              const Text('同一選手選択上限', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              TextField(
                controller: _same,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(isDense: true),
              ),
              const SizedBox(height: 12),
              const Text('ポイント計算方式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                isExpanded: true,
                value: _point,
                items: [
                  for (final entry in predictPointLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _saving ? null : (value) => setState(() => _point = value ?? _point),
              ),
              const SizedBox(height: 16),
              const Text('対象タイトル', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (_titles.isEmpty)
                const Text('対象タイトルはまだありません', style: TextStyle(fontSize: 12))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final title in _titles)
                      InputChip(
                        label: Text(predictDisplayTitle(title.title), style: TextStyle(color: predictStatsColor(title: title.title, pitcher: title.pitcher), fontWeight: FontWeight.w700)),
                        backgroundColor: predictStatsColor(title: title.title, pitcher: title.pitcher)?.withValues(alpha: 0.12),
                        side: predictStatsColor(title: title.title, pitcher: title.pitcher) == null
                            ? null
                            : BorderSide(color: predictStatsColor(title: title.title, pitcher: title.pitcher)!),
                        onDeleted: _saving ? null : () => setState(() => _removeTitle(title)),
                      ),
                  ],
                ),
              if (available.isNotEmpty) ...[
                const SizedBox(height: 6),
                DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('タイトルを追加'),
                  items: [
                    for (final item in available)
                      DropdownMenuItem(
                        value: item.title,
                        child: Text(item.title, style: TextStyle(color: predictStatsColor(title: item.title, pitcher: item.pitcher), fontWeight: FontWeight.w700)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _addTitle(value));
                        },
                ),
              ],
              Wrap(
                spacing: 8,
                children: [
                  for (final title in const ['チーム順位', '優勝'])
                    if (!_titles.any((item) => item.title == title || (title == '優勝' && item.title == '日本一')))
                      TextButton(
                        onPressed: _saving ? null : () => setState(() => _addTitle(title)),
                        child: Text('${predictDisplayTitle(title)}を追加'),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('チーム順位', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              if (_teamClosed)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('予想期限を過ぎているため変更できません', style: TextStyle(fontSize: 12, color: Color(0xFFC62828))),
                ),
              const SizedBox(height: 6),
              if (_users.isEmpty)
                const Text('参加ユーザーがいないため順位を編集できません', style: TextStyle(fontSize: 12))
              else ...[
                predictJapanBanner(),
                const SizedBox(height: 4),
                _predictTable(
                  rows: [
                    (
                      label: '日本一',
                      color: null,
                      cells: [
                        for (final user in _users) _slotView('c|${_asInt(user['id'])}', 'team', 0),
                      ],
                    ),
                    if (_titles.any((title) => title.title == '沢村賞'))
                      (
                        label: '沢村賞',
                        color: const Color(0xFF1565C0),
                        cells: [
                          for (final user in _users) _slotView('p|沢村賞|0|${_asInt(user['id'])}', 'player', 0),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final league in _predictLeagues) ...[
                  predictLeagueBanner(league.name),
                  const SizedBox(height: 4),
                  _predictTable(
                    rows: [
                      for (var rank = 1; rank <= 6; rank++)
                        (
                          label: '$rank位',
                          color: null,
                          cells: [
                            for (final user in _users) _slotView('r|${league.id}|$rank|${_asInt(user['id'])}', 'team', league.id),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 12),
              const Text('個人成績予想', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              if (_playerClosed)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('予想期限を過ぎているため変更できません', style: TextStyle(fontSize: 12, color: Color(0xFFC62828))),
                ),
              const SizedBox(height: 4),
              if (orderedPlayerTitles.isEmpty)
                const Text('個人成績の対象タイトルを追加すると選手を入力できます', style: TextStyle(fontSize: 12))
              else
                for (final league in _predictLeagues) ...[
                  const SizedBox(height: 6),
                  predictLeagueBanner(league.name),
                  const SizedBox(height: 4),
                  _predictTable(
                    rows: [
                      for (final title in orderedPlayerTitles)
                        (
                          label: title.title,
                          color: predictStatsColor(title: title.title, pitcher: title.pitcher),
                          cells: [
                            for (final user in _users) _slotView(_playerKey(title.title, league.id, _asInt(user['id'])), 'player', league.id),
                          ],
                        ),
                    ],
                  ),
                ],
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(_notice!, style: const TextStyle(color: Color(0xFF1565C0), fontSize: 13)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
      ],
    );
  }

  Widget _dateButton(String label, TextEditingController controller) {
    final text = controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _pickDate(controller),
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(text.isEmpty ? '日付を選択' : text, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            if (text.isNotEmpty)
              TextButton(
                onPressed: _saving ? null : () => setState(() => controller.text = ''),
                child: const Text('クリア'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _proposalBox() {
    final proposal = _proposal;
    if (proposal == null) return const SizedBox.shrink();
    final approvals = [
      for (final row in (proposal['approvals'] is List ? proposal['approvals'] as List : const []))
        if (row is Map) _asInt(row['id_user']),
    ];
    final waiting = [
      for (final user in _users)
        if (!approvals.contains(_asInt(user['id']))) _userLabel(user),
    ];
    final select = predictSelectLabels['${proposal['code_select']}'] ?? '${proposal['code_select']}';
    final point = predictPointLabels['${proposal['code_point']}'] ?? '${proposal['code_point']}';
    final team = _dateOnly('${proposal['date_limit_team'] ?? ''}');
    final player = _dateOnly('${proposal['date_limit_player'] ?? ''}');
    final mine = widget.viewerId;
    final already = mine != null && approvals.contains(mine);
    final member = mine != null && _users.any((user) => _asInt(user['id']) == mine);
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFFFFF8E1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '変更案（${proposal['proposer_name'] ?? ''}） ${approvals.length}/${_users.length}人が賛成',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('チーム順位の期限 ${team.isEmpty ? 'なし' : team}　個人成績予想の期限 ${player.isEmpty ? 'なし' : player}', style: const TextStyle(fontSize: 12)),
          Text('$select　上限${proposal['int_same_player_limit'] ?? ''}　$point', style: const TextStyle(fontSize: 12)),
          Text(waiting.isEmpty ? '全員が賛成しています' : '未賛成: ${waiting.join('、')}', style: const TextStyle(fontSize: 12)),
          if (member && !already)
            TextButton(onPressed: _saving ? null : _vote, child: const Text('賛成する')),
        ],
      ),
    );
  }

  Widget _predictTable({
    required List<({String label, Color? color, List<Widget> cells})> rows,
  }) {
    const gridLine = Color(0xFFD0D0D6);
    return Table(
      border: TableBorder.all(color: gridLine, width: 1),
      columnWidths: {
        0: const FixedColumnWidth(72),
        for (var i = 1; i <= _users.length; i++) i: const FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox(height: 24),
            for (final user in _users)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                child: Text(
                  _userLabel(user),
                  textAlign: TextAlign.left,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: parseColorNameOrNull('${user['color'] ?? ''}') ?? const Color(0xFF37474F)),
                ),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  row.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: row.color),
                ),
              ),
              for (final cell in row.cells)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
                  child: cell,
                ),
            ],
          ),
      ],
    );
  }

  Widget _slotView(String key, String kind, int leagueId) {
    final slot = _slots[key] ?? _slot(key);
    if (!slot.editing) {
      final empty = slot.confirmed.trim().isEmpty;
      final editable = _slotOpen(key, kind);
      return Row(
        children: [
          Expanded(
            child: Text(
              empty ? '未設定' : slot.confirmed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: empty ? Colors.black38 : Colors.black87),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: editable
                ? IconButton(
                    tooltip: '修正',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _saving ? null : () => _beginEdit(key),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: slot.controller,
                autofocus: true,
                decoration: const InputDecoration(isDense: true, hintText: '名前を入力'),
                onChanged: (_) => _searchSlot(key, kind, leagueId),
              ),
            ),
            TextButton(
              onPressed: _saving ? null : () => _cancelEdit(key),
              child: const Text('中止'),
            ),
          ],
        ),
        for (final item in slot.suggestions)
          InkWell(
            onTap: () => _confirmSlot(key, '${item['name'] ?? ''}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${item['team'] ?? ''}'.trim().isEmpty ? '${item['name'] ?? ''}' : '${item['name'] ?? ''}　${item['team']}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  void _beginEdit(String key) {
    final kind = key.startsWith('p|') ? 'player' : 'team';
    if (!_slotOpen(key, kind)) return;
    final slot = _slots[key];
    if (slot == null) return;
    setState(() {
      slot.editing = true;
      slot.controller.text = slot.confirmed;
      slot.suggestions = const [];
      slot.searchGen++;
    });
  }

  void _cancelEdit(String key) {
    final slot = _slots[key];
    if (slot == null) return;
    setState(() {
      slot.searchGen++;
      slot.editing = false;
      slot.controller.text = slot.confirmed;
      slot.suggestions = const [];
    });
  }

  void _confirmSlot(String key, String name) {
    final slot = _slots[key];
    final trimmed = name.trim();
    if (slot == null || trimmed.isEmpty) return;
    setState(() {
      slot.searchGen++;
      slot.confirmed = trimmed;
      slot.controller.text = trimmed;
      slot.editing = false;
      slot.suggestions = const [];
      if (key.startsWith('p|') && _waiverActive && !_waiverSeed.contains(key)) _waiverPick = key;
    });
  }

  void _searchSlot(String key, String kind, int leagueId) {
    final slot = _slots[key];
    if (slot == null) return;
    final gen = ++slot.searchGen;
    final query = slot.controller.text.trim();
    if (query.isEmpty || widget.onSearch == null) {
      setState(() => slot.suggestions = const []);
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      if (!mounted || slot.searchGen != gen) return;
      try {
        final found = await widget.onSearch!(kind, leagueId, query);
        if (!mounted || slot.searchGen != gen) return;
        setState(() => slot.suggestions = found);
      } catch (_) {
        if (!mounted || slot.searchGen != gen) return;
        setState(() => slot.suggestions = const []);
      }
    });
  }

  String _viewerName(int? id) {
    for (final user in _users) {
      if (_asInt(user['id']) == id) return _userLabel(user);
    }
    return '';
  }

  String _userLabel(Map<String, dynamic> user) {
    final name = '${user['name'] ?? ''}'.trim();
    return name.isEmpty ? 'ユーザー${_asInt(user['id'])}' : name;
  }
}

class _PredictNameDialog extends StatefulWidget {
  final int groupId;
  final String name;
  final RenamePredictGroup? onSave;

  const _PredictNameDialog({
    required this.groupId,
    required this.name,
    required this.onSave,
  });

  @override
  State<_PredictNameDialog> createState() => _PredictNameDialogState();
}

class _PredictNameDialogState extends State<_PredictNameDialog> {
  late final TextEditingController _name;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'グループ名を入力してください');
      return;
    }
    if (widget.onSave == null) {
      setState(() => _error = '保存できませんでした');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave!(widget.groupId, name);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('グループ名'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(isDense: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
      ],
    );
  }
}

const _battingTitles = {'打率', '本塁打', '打点', '盗塁', '出塁率', 'MVP'};
const _pitchingTitles = {'防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'HP', '中継ぎ', '沢村賞'};

Color predictLeagueColor(String name) {
  for (final org in const [OrgConfig.npb, OrgConfig.mlb]) {
    for (final league in org.leagues) {
      if (name == league.name) return league.color;
    }
  }
  if (name.contains('セ')) return OrgConfig.npb.leagueColor(1);
  if (name.contains('パ')) return OrgConfig.npb.leagueColor(2);
  return const Color(0xFF455A64);
}

Widget predictJapanBanner() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFF8E1B2C), borderRadius: BorderRadius.circular(4)),
    child: const Text('NPB', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
  );
}

Widget predictLeagueBanner(String name) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: predictLeagueColor(name), borderRadius: BorderRadius.circular(4)),
    child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
  );
}

Color? predictStatsColor({required String title, bool? pitcher}) {
  if (_specialPredictTitles.contains(title)) return null;
  final pitching = pitcher ?? _pitchingTitles.contains(title);
  if (pitching) return const Color(0xFF1565C0);
  if (pitcher == false || _battingTitles.contains(title)) return const Color(0xFFC62828);
  return null;
}

List<Map<String, dynamic>> _maps(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

int _asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

/// 予想期限の候補。選んだ日付（YYYY-MM-DD）を返す。閉じたら null。
Future<String?> pickPredictDeadline(
  BuildContext context,
  int year, {
  Map<String, dynamic>? marks,
  String current = '',
}) {
  final options = predictDeadlineOptions(year, marks);
  final selected = current.trim().length >= 10 ? current.trim().substring(0, 10) : '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('期限を選択', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 340,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(option.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  trailing: Text(option.date, style: const TextStyle(fontSize: 13, color: Color(0xFF546E7A))),
                  selected: option.date == selected,
                  onTap: () => Navigator.of(context).pop(option.date),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
      ],
    ),
  );
}

class _PredictGroupCreateDialog extends StatefulWidget {
  final SearchPredictUsers? onSearch;
  final CreatePredictGroup? onCreate;

  const _PredictGroupCreateDialog({required this.onSearch, required this.onCreate});

  @override
  State<_PredictGroupCreateDialog> createState() => _PredictGroupCreateDialogState();
}

class _PredictGroupCreateDialogState extends State<_PredictGroupCreateDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _query = TextEditingController();
  final List<Map<String, dynamic>> _picked = [];
  List<Map<String, dynamic>> _found = const [];
  String? _error;
  bool _saving = false;
  int _gen = 0;

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  void _search(String value) {
    final gen = ++_gen;
    final query = value.trim();
    if (query.isEmpty || widget.onSearch == null) {
      setState(() => _found = const []);
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      if (!mounted || gen != _gen) return;
      final found = await widget.onSearch!(query);
      if (!mounted || gen != _gen) return;
      setState(() => _found = found);
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'グループ名を入力してください');
      return;
    }
    if (widget.onCreate == null) {
      setState(() => _error = '作成できませんでした');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onCreate!(name, [for (final user in _picked) _asInt(user['id'])]);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('予想グループを追加'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('グループ名', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            TextField(controller: _name, decoration: const InputDecoration(isDense: true)),
            const SizedBox(height: 12),
            const Text('招待するユーザー', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            TextField(
              controller: _query,
              decoration: const InputDecoration(isDense: true, hintText: '名前を検索'),
              onChanged: _search,
            ),
            if (_picked.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final user in _picked)
                    InputChip(
                      label: Text('${user['name'] ?? ''}'),
                      onDeleted: _saving
                          ? null
                          : () => setState(() => _picked.removeWhere((item) => _asInt(item['id']) == _asInt(user['id']))),
                    ),
                ],
              ),
            for (final user in _found)
              if (!_picked.any((item) => _asInt(item['id']) == _asInt(user['id'])))
                InkWell(
                  onTap: _saving
                      ? null
                      : () => setState(() {
                            _picked.add(user);
                            _found = const [];
                            _query.clear();
                            _gen++;
                          }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${user['name'] ?? ''}', style: const TextStyle(fontSize: 14)),
                  ),
                ),
            const SizedBox(height: 8),
            const Text('招待したユーザーが参加を承認すると、グループの参加者になります。', style: TextStyle(fontSize: 12, color: Color(0xFF546E7A))),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
            ],
          ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        TextButton(onPressed: _saving ? null : _create, child: const Text('作成')),
      ],
    );
  }
}

class _PredictYearDialog extends StatefulWidget {
  final int groupId;
  final Set<int> taken;
  final CreatePredictYear? onCreate;

  const _PredictYearDialog({required this.groupId, required this.taken, required this.onCreate});

  @override
  State<_PredictYearDialog> createState() => _PredictYearDialogState();
}

class _PredictYearDialogState extends State<_PredictYearDialog> {
  late int _year;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _year = widget.taken.contains(now) ? now + 1 : now;
  }

  Future<void> _create() async {
    if (widget.taken.contains(_year)) {
      setState(() => _error = '$_year年の予想はすでにあります');
      return;
    }
    if (widget.onCreate == null) {
      setState(() => _error = '追加できませんでした');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onCreate!(widget.groupId, _year);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var year = DateTime.now().year + 1; year >= DateTime.now().year - 5; year--) year];
    return AlertDialog(
      title: const Text('年度を追加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('新しい年度の予想を登録します。対象タイトルは直前の年度からコピーします。', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          DropdownButton<int>(
            isExpanded: true,
            value: years.contains(_year) ? _year : years.first,
            items: [
              for (final year in years)
                DropdownMenuItem(value: year, child: Text(widget.taken.contains(year) ? '$year年（登録済み）' : '$year年')),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _year = value);
                  },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        TextButton(onPressed: _saving ? null : _create, child: const Text('登録')),
      ],
    );
  }
}
