import 'SeasonTable.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../logic/season_schedule.dart';
import 'EventCalendar.dart';

class SeasonScheduleLoader extends StatefulWidget {
  const SeasonScheduleLoader(
      {super.key,
      required this.org,
      required this.year,
      required this.builder});
  final OrgConfig org;
  final int year;
  final Widget Function(List<Map<String, dynamic>>) builder;
  @override
  State<SeasonScheduleLoader> createState() => _SeasonScheduleLoaderState();
}

class _SeasonScheduleLoaderState extends State<SeasonScheduleLoader> {
  List<Map<String, dynamic>> _games = [];
  String? _error;
  bool _loading = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SeasonScheduleLoader old) {
    super.didUpdateWidget(old);
    if (old.org.kind != widget.org.kind || old.year != widget.year) {
      _games = [];
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
      final response = await http
          .get(Env.api(
              '/season-schedule?org=${widget.org.kind.name}&year=${widget.year}'))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) throw const FormatException('日程取得失敗');
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted || request != _request) return;
      setState(() => _games = listMapFromJson(data['games']));
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = '日程・対戦結果を取得できませんでした');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Row(children: [
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _load, child: const Text('再読み込み'))
          ]),
        Expanded(child: widget.builder(_games))
      ]);
}

class SeasonCalendarBoard extends StatefulWidget {
  const SeasonCalendarBoard(
      {super.key, required this.org, required this.year, required this.events});
  final OrgConfig org;
  final int year;
  final List<Map<String, dynamic>> events;
  @override
  State<SeasonCalendarBoard> createState() => _SeasonCalendarBoardState();
}

class _SeasonCalendarBoardState extends State<SeasonCalendarBoard> {
  late int _year = widget.year;
  @override
  void didUpdateWidget(covariant SeasonCalendarBoard old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) _year = widget.year;
  }

  @override
  Widget build(BuildContext context) => SeasonScheduleLoader(
      org: widget.org,
      year: _year,
      builder: (games) => EventCalendar(
            events: widget.events,
            games: games,
            initialMonth: DateTime(widget.year,
                widget.year == DateTime.now().year ? DateTime.now().month : 3),
            onMonthChanged: (m) {
              if (m.year != _year) setState(() => _year = m.year);
            },
          ));
}

class InterleagueStandings extends StatelessWidget {
  const InterleagueStandings(
      {super.key, required this.teams, required this.games});
  final List<Map<String, dynamic>> teams, games;
  @override
  Widget build(BuildContext context) {
    final rows = interleagueStandings(teams, games);
    final standings = [
      for (var i = 0; i < rows.length; i++)
        {
          ...rows[i],
          'source_league_id': rows[i]['id_league'],
          'id_league': 0,
          'int_rank': rows[i]['pct'] == null
              ? 1000
              : rows.indexWhere((r) => r['pct'] == rows[i]['pct']) + 1,
          'int_game': rows[i]['wins'] + rows[i]['losses'] + rows[i]['draws'],
          'int_win': rows[i]['wins'],
          'int_lose': rows[i]['losses'],
          'int_draw': rows[i]['draws'],
          'pct_win': (rows[i]['pct'] as double?)?.toStringAsFixed(3),
          'game_behind': rows[i]['pct'] == null
              ? '—'
              : i == 0
                  ? '-'
                  : ((rows[i - 1]['wins'] -
                              rows[i - 1]['losses'] -
                              rows[i]['wins'] +
                              rows[i]['losses']) /
                          2)
                      .toStringAsFixed(1),
        }
    ];
    return SeasonTableBlock(
        standings: standings,
        stats: const [],
        onlyLeagueId: 0,
        showPredictionColumns: false,
        showNpbLeagueColumn: true,
        pane: SeasonPane.standings,
        portraitLayout: true,
        org: const OrgConfig(
            kind: OrgKind.npb,
            label: '交流戦',
            logoAsset: 'backend/assets/images/logo_npb.png',
            tabColor: Colors.yellow,
            tabForeground: Colors.black,
            leagues: [OrgLeague(id: 0, name: '交流戦順位', color: Colors.yellow)]));
  }
}
