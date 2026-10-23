import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../widgets/baseball_loading.dart';
import 'player_detail_dialog.dart';

class InjuriesBoard extends StatefulWidget {
  const InjuriesBoard({super.key, required this.org});
  final String org;
  @override
  State<InjuriesBoard> createState() => _InjuriesBoardState();
}

class _InjuriesBoardState extends State<InjuriesBoard> {
  List<Map<String, dynamic>>? _players;
  String? _error;
  int _request = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(InjuriesBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.org != widget.org) _load();
  }
  Future<void> _load() async {
    final request = ++_request;
    setState(() { _players = null; _error = null; });
    try {
      final response = await http.get(Env.api('/injuries').replace(queryParameters: {'org': widget.org})).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['players'] is! List) throw const FormatException();
      if (mounted && request == _request) setState(() => _players = listMapFromJson(data['players']));
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = '怪我人情報を取得できませんでした。');
    }
  }
  String _text(dynamic value) => value == null || '$value'.trim().isEmpty ? '不明' : '$value';
  static const _columns = <int, TableColumnWidth>{0: FixedColumnWidth(110), 1: FixedColumnWidth(140), 2: FlexColumnWidth(), 3: FixedColumnWidth(130), 4: FixedColumnWidth(160)};
  Widget _table(List<Widget> cells, {bool header = false}) => Table(
    columnWidths: _columns,
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    border: TableBorder.all(color: const Color(0xffd9dfe5), width: .5),
    children: [TableRow(decoration: BoxDecoration(color: header ? const Color(0xffe9edf2) : Colors.white), children: cells)],
  );
  Widget _cell(String value, {bool header = false}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), child: Text(value, style: TextStyle(fontSize: 12, fontWeight: header ? FontWeight.bold : FontWeight.normal)));
  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('再読み込み'))]));
    if (_players == null) return const Center(child: BaseballLoading());
    final players = _players!;
    return PlayerDetailScope(org: widget.org, year: DateTime.now().year, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
        Expanded(child: Text('🤕怪我人（${players.length}人）', style: const TextStyle(fontWeight: FontWeight.bold))),
        IconButton(tooltip: '再読み込み', onPressed: _load, icon: const Icon(Icons.refresh)),
      ])),
      const SizedBox(height: 8),
      Expanded(child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: math.max(820, constraints.maxWidth), height: constraints.maxHeight, child: Column(children: [
          _table([for (final label in ['球団', '選手名', '怪我の内容', '負傷時期', '復帰時期']) _cell(label, header: true)], header: true),
          Expanded(child: ListView.builder(key: const ValueKey('injuries-grid-scroll'), itemCount: players.length + 1, itemBuilder: (context, index) {
            if (index == players.length) { return Align(alignment: Alignment.centerLeft,
              child: SizedBox(width: constraints.maxWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (players.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('怪我人情報は登録されていません。')),
                const Padding(key: ValueKey('injuries-grid-notes'), padding: EdgeInsets.all(12), child: Text('登録済みの最新情報（選択年度に依存しません）。復帰時期は予定・全治期間を含み、不明な項目は「不明」と表示します。', style: TextStyle(fontSize: 11, color: Colors.black54))),
              ])));
            }

            final player = players[index];
            final background = parseColorNameOrNull('${player['color_back']}') ?? Colors.blueGrey;
            final foreground = parseColorNameOrNull('${player['color_font']}') ?? (background.computeLuminance() > .179 ? Colors.black : Colors.white);
            return _table([
              TableCell(verticalAlignment: TableCellVerticalAlignment.fill, child: Container(color: background, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(10), child: Text(_text(player['name_team']), style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.bold)))),
              PlayerNameLink(player: player, child: _cell(_text(player['name_player']))),
              _cell('${player['estimated'] == true ? '推定：' : ''}${_text(player['injury'])}'), _cell(_text(player['injured_at'])), _cell(_text(player['return_at'])),
            ]);
          })),
        ])),
      ))),
    ]));
  }
}
