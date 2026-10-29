import 'package:koko_shared/championship_calendar.dart';
import 'package:koko_shared/championship_schedule.dart';
import 'dart:async';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import 'SeasonTable.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../logic/season_schedule.dart';
import 'EventCalendar.dart';

Future<Map<String, dynamic>> _fetchSeasonSchedule(OrgConfig org, int year) async {
  final response = await http.get(Env.api('/season-schedule?org=${org.kind.name}&year=$year'))
      .timeout(const Duration(seconds: 25));
  if (response.statusCode != 200) throw const FormatException('日程取得失敗');
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
}

/// HOME week/month views share successful results for this app session.
class HomeCalendarCache {
  static final _saved = <String, Map<String, dynamic>>{};
  static final _loadedAt = <String, DateTime>{};
  static final _pending = <String, Future<Map<String, dynamic>>>{};
  static String _key(OrgConfig org, int year) => '${org.kind.name}:$year';
  static bool contains(OrgConfig org, int year) => _saved.containsKey(_key(org, year));
  static Future<Map<String, dynamic>> read(OrgConfig org, int year) {
    final key = _key(org, year);
    final saved = _saved[key];
    final loadedAt = _loadedAt[key];
    if (saved != null && loadedAt != null && DateTime.now().difference(loadedAt) < const Duration(minutes: 1)) return Future.value(saved);
    return _pending.putIfAbsent(key, () async {
      try {
        final data = await _fetchSeasonSchedule(org, year);
        if (data['pending'] != true) {
          _saved[key] = data;
          _loadedAt[key] = DateTime.now();
        }
        return data;
      } finally {
        _pending.remove(key);
      }
    });
  }
  @visibleForTesting
  static void clear() { _saved.clear(); _loadedAt.clear(); _pending.clear(); }
}

class SeasonScheduleLoader extends StatefulWidget {
  const SeasonScheduleLoader(
      {super.key,
      required this.org,
      required this.year,
      required this.builder,
      this.calendarBuilder,
      this.reuseLoaded = false});
  final bool reuseLoaded;
  final OrgConfig org;
  final int year;
  final Widget Function(List<Map<String, dynamic>>) builder;
  final Widget Function(List<Map<String, dynamic>>, List<Map<String, dynamic>>)?
      calendarBuilder;
  @override
  State<SeasonScheduleLoader> createState() => _SeasonScheduleLoaderState();
}

class _SeasonScheduleLoaderState extends State<SeasonScheduleLoader>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _events = [];
  String? _error;
  bool _loading = true;
  bool _showLoading = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _configureRefresh();
  }

  void _configureRefresh() {
    _refreshTimer?.cancel();
    if (!widget.reuseLoaded) {
      _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!_loading) _load(silent: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SeasonScheduleLoader old) {
    super.didUpdateWidget(old);
    if (old.reuseLoaded != widget.reuseLoaded) _configureRefresh();
    if (old.org.kind != widget.org.kind || old.year != widget.year) {
      _games = [];
      _events = [];
      _load();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.reuseLoaded && state == AppLifecycleState.resumed && !_loading) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    final request = ++_request;
    _loading = true;
    if (!silent) {
      setState(() {
        _error = null;
        _showLoading = !widget.reuseLoaded || !HomeCalendarCache.contains(widget.org, widget.year);
      });
    }
    try {
      final data = await (widget.reuseLoaded
          ? HomeCalendarCache.read(widget.org, widget.year)
          : _fetchSeasonSchedule(widget.org, widget.year));
      if (!mounted || request != _request) return;
      if (data['pending'] == true) {
        setState(() => _error = '${data['message']}');
        return;
      }
      setState(() {
        _games = championshipSchedule(listMapFromJson(data['games']));
        _events = championshipCalendarEvents(listMapFromJson(data['events']), _games);
        _error = null;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = '日程・対戦結果を取得できませんでした');
      }
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _showLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_showLoading) const BaseballLoading(compact: true),
        if (_error != null)
          Row(children: [
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _load, child: const Text('再読み込み'))
          ]),
        Expanded(
            child: widget.calendarBuilder?.call(_games, _events) ??
                widget.builder(_games))
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
      builder: (_) => const SizedBox.shrink(),
      calendarBuilder: (games, events) => EventCalendar(
            events: [...widget.events, ...events],
            games: games,
            initialMonth: DateTime(widget.year,
                widget.year == DateTime.now().year ? DateTime.now().month : 3),
            onMonthChanged: (m) {
              if (m.year != _year) setState(() => _year = m.year);
            },
          ));
}

/// HOMEでは両団体の試合とイベントを同じ月間カレンダーに表示する。
class HomeSeasonCalendar extends StatefulWidget {
  const HomeSeasonCalendar({super.key, required this.year, this.weekStart, this.weekCount = 1}) : assert(weekCount > 0);
  final int year;
  final DateTime? weekStart;
  final int weekCount;
  @override
  State<HomeSeasonCalendar> createState() => _HomeSeasonCalendarState();
}

class _HomeSeasonCalendarState extends State<HomeSeasonCalendar> {
  late int _year = widget.year;
  late DateTime? _weekStart = widget.weekStart;
  @override
  void didUpdateWidget(covariant HomeSeasonCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.weekStart != widget.weekStart) {
      _year = widget.year;
      _weekStart = widget.weekStart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = _weekStart == null ? {_year} : {
      _weekStart!.year,
      _weekStart!.add(Duration(days: 7 * widget.weekCount - 1)).year,
    };
    final sources = [for (final year in years)
      for (final org in [OrgConfig.npb, OrgConfig.mlb]) (year: year, org: org)];
    Widget load(int index, List<Map<String, dynamic>> games, List<Map<String, dynamic>> events) {
      if (index < sources.length) {
        final source = sources[index];
        return SeasonScheduleLoader(
          org: source.org, year: source.year, reuseLoaded: true,
          builder: (_) => const SizedBox.shrink(),
          calendarBuilder: (nextGames, nextEvents) => load(index + 1,
              [...games, ...nextGames], [...events, ...nextEvents]),
        );
      }
      return EventCalendar(
        games: games,
        weekStart: _weekStart,
        weekCount: widget.weekCount,
        onWeekChanged: (week) => setState(() => _weekStart = week),
        events: {
          for (final event in events)
            '${event['title_event']}|${event['date_from_temp']}|${event['date_to']}|${event['event_category']}': event,
        }.values.toList(),
        initialMonth: DateTime(widget.year, widget.year == DateTime.now().year ? DateTime.now().month : 3),
        onMonthChanged: (month) {
          if (month.year != _year) setState(() => _year = month.year);
        },
      );
    }
    return load(0, [], []);
  }
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
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SeasonTableBlock(
          standings: standings,
          stats: const [],
          onlyLeagueId: 0,
          showNpbLeagueColumn: true,
          pane: SeasonPane.standings,
          portraitLayout: true,
          org: const OrgConfig(
              kind: OrgKind.npb,
              label: '交流戦',
              logoAsset: 'backend/assets/images/logo_npb.png',
              tabColor: Colors.yellow,
              tabForeground: Colors.black,
              leagues: [
                OrgLeague(id: 0, name: '交流戦順位', color: Colors.yellow)
              ])),
    );
  }
}
