import 'GamesBoard.dart' show teamLogoVisual;
import 'package:flutter/material.dart';
import '../logic/season_schedule.dart';

/// イベント日程の月間カレンダー。左のカテゴリ高さは News のタグ（20）に揃える。
class EventCalendar extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> games;
  final DateTime? initialMonth;
  final ValueChanged<DateTime>? onMonthChanged;

  const EventCalendar(
      {super.key,
      required this.events,
      this.games = const [],
      this.initialMonth,
      this.onMonthChanged});

  @override
  State<EventCalendar> createState() => _EventCalendarState();
}

class _EventCalendarState extends State<EventCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = widget.initialMonth ?? DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  void didUpdateWidget(covariant EventCalendar old) {
    super.didUpdateWidget(old);
    if (old.initialMonth != widget.initialMonth &&
        widget.initialMonth != null) {
      _month = widget.initialMonth!;
    }
  }

  void _move(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    widget.onMonthChanged?.call(_month);
  }

  List<Map<String, dynamic>> _gamesOn(DateTime? d) => d == null
      ? []
      : widget.games.where((g) => g['date'] == scheduleDate(d)).toList();
  DateTime? _dayOf(dynamic value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return null;
    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Color _parse(dynamic name, Color fallback) {
    const m = {
      'red': 0xFFF44336,
      'green': 0xFF4CAF50,
      'blue': 0xFF0000FF,
      'navy': 0xFF001F3F,
      'royalblue': 0xFF4169E1,
      'orange': 0xFFFF9800,
      'yellow': 0xFFFFEB3B,
      'gold': 0xFFFFD700,
      'lime': 0xFFCDDC39,
      'black': 0xFF000000,
      'gray': 0xFF9E9E9E,
      'grey': 0xFF9E9E9E,
      'crimson': 0xFFDC143C,
      'lightgreen': 0xFF8BC34A,
      'white': 0xFFFFFFFF,
    };
    final key = '$name'.toLowerCase().trim();
    final hex = m[key];
    return hex == null ? fallback : Color(hex);
  }

  bool _covers(Map<String, dynamic> event, DateTime day) {
    final from = _dayOf(event['date_from_temp']);
    if (from == null) return false;
    final to = _dayOf(event['date_to']) ?? from;
    final end = to.isBefore(from) ? from : to;
    return !day.isBefore(from) && !day.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday % 7;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    const weekdays = ['日', '月', '火', '水', '木', '金', '土'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left, size: 18),
              ),
              Expanded(
                child: Text(
                  '${_month.year}年${_month.month}月',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _move(1),
                icon: const Icon(Icons.chevron_right, size: 18),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final label in weekdays)
              Expanded(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mins = [
                for (var r = 0; r < rows; r++) _weekMinHeight(r, lead, days)
              ];
              final sum =
                  mins.fold<double>(0, (total, height) => total + height);
              final available = constraints.maxHeight;
              final grow = available.isFinite && rows > 0 && available > sum
                  ? (available - sum) / rows
                  : 0.0;
              final grid = Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    _week(r, lead, days, constraints.maxWidth, mins[r] + grow),
                ],
              );
              if (grow > 0) return grid;
              return SingleChildScrollView(primary: false, child: grid);
            },
          ),
        ),
      ],
    );
  }

  DateTime? _cellDate(int index, int lead, int days) {
    final dayNum = index - lead + 1;
    if (dayNum < 1 || dayNum > days) return null;
    return DateTime(_month.year, _month.month, dayNum);
  }

  double _weekMinHeight(int row, int lead, int days) {
    final bars = _barsForWeek(row, lead, days);
    const barH = 14.0;
    final lanes = bars.isEmpty
        ? 0
        : bars.map((bar) => bar.lane).reduce((a, b) => a > b ? a : b) + 1;
    final maxGames = [
      for (var c = 0; c < 7; c++)
        _gamesOn(_cellDate(row * 7 + c, lead, days)).length
    ].reduce((a, b) => a > b ? a : b);
    return 26.0 + lanes * (barH + 2) + maxGames * 17;
  }

  Widget _week(int row, int lead, int days, double width, double height) {
    final cellW = width / 7;
    final bars = _barsForWeek(row, lead, days);
    const barH = 14.0;
    final today = DateTime.now();
    final lanes = bars.isEmpty
        ? 0
        : bars.map((b) => b.lane).reduce((a, b) => a > b ? a : b) + 1;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(builder: (context) {
                    final date = _cellDate(row * 7 + c, lead, days);
                    final isToday = date != null &&
                        date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    return Container(
                      padding: const EdgeInsets.only(top: 1, left: 2),
                      decoration: BoxDecoration(
                        color: isToday ? const Color(0xFFFFF59D) : Colors.white,
                        border: Border.all(color: Colors.black26),
                      ),
                      alignment: Alignment.topLeft,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(date == null ? '' : '${date.day}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.1,
                                    fontWeight: FontWeight.bold)),
                            SizedBox(height: lanes * 16.0 + 5),
                            for (final game in _gamesOn(date))
                              SizedBox(
                                  height: 17,
                                  child: Tooltip(
                                      message:
                                          '${scheduleMatchup(game)} ${game['time'] ?? ''} ${game['stadium'] ?? ''}',
                                      child: ScheduleGameTile(game: game)))
                          ]),
                    );
                  }),
                ),
            ],
          ),
          for (final bar in bars)
            Positioned(
                left: bar.start * cellW + 2,
                width: (bar.end - bar.start + 1) * cellW - 4,
                top: 16 + bar.lane * (barH + 2),
                height: barH,
                child: Tooltip(
                  message: bar.detail.isEmpty
                      ? bar.title
                      : "${bar.title}\n${bar.detail}",
                  triggerMode: TooltipTriggerMode.tap,
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(color: bar.color),
                    child: Text(
                      bar.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.1,
                          color: bar.font,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  List<_EventBar> _barsForWeek(int row, int lead, int days) {
    final placed = <_EventBar>[];
    final laneEnds = <int>[];
    final items = <({
      int start,
      int end,
      String title,
      String detail,
      Color color,
      Color font
    })>[];
    for (final event in widget.events) {
      int? start;
      int? end;
      for (var c = 0; c < 7; c++) {
        final date = _cellDate(row * 7 + c, lead, days);
        if (date == null || !_covers(event, date)) continue;
        start ??= c;
        end = c;
      }
      if (start == null || end == null) continue;
      final color =
          _parse(event['event_category_color_back'], const Color(0xFF1565C0));
      items.add((
        start: start,
        end: end,
        title: '${event['title_event'] ?? ''}',
        detail: '${event['detail'] ?? ''}',
        color: color,
        font: _parse(event['event_category_color_font'], Colors.white),
      ));
    }
    items.sort((a, b) => a.start.compareTo(b.start));
    for (final item in items) {
      var lane = 0;
      while (lane < laneEnds.length && laneEnds[lane] >= item.start) {
        lane++;
      }
      if (lane == laneEnds.length) {
        laneEnds.add(item.end);
      } else {
        laneEnds[lane] = item.end;
      }
      placed.add(_EventBar(
          start: item.start,
          end: item.end,
          lane: lane,
          title: item.title,
          detail: item.detail,
          color: item.color,
          font: item.font));
    }
    return placed;
  }
}

class _EventBar {
  final int start;
  final int end;
  final int lane;
  final String title;
  final String detail;
  final Color color;
  final Color font;

  const _EventBar({
    required this.start,
    required this.end,
    required this.lane,
    required this.title,
    required this.detail,
    required this.color,
    required this.font,
  });
}

class ScheduleGameTile extends StatelessWidget {
  const ScheduleGameTile({super.key, required this.game});
  final Map<String, dynamic> game;
  Widget logo(String side) {
    final raw =
        '${game['name_${side}_logo'] ?? game['name_$side'] ?? ''}'.trim();
    const names = {
      '巨': '巨人',
      '神': '阪神',
      '中': '中日',
      'ヤ': 'ヤクルト',
      '広': '広島',
      'De': 'DeNA',
      'ソ': 'ソフトバンク',
      '日': '日本ハム',
      'ロ': 'ロッテ',
      '西': '西武',
      '楽': '楽天',
      'オ': 'オリックス'
    };
    final name = names[raw] ?? raw;
    final visual =
        teamLogoVisual(name, abbrev: '${game['${side}_code'] ?? ''}');
    Widget fallback() =>
        const Icon(Icons.sports_baseball, size: 14, color: Colors.grey);
    return Semantics(
        label: name,
        child: SizedBox(
            width: 16,
            height: 16,
            child: visual.asset != null
                ? Image.asset(visual.asset!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => fallback())
                : visual.networkUrl != null
                    ? Image.network(visual.networkUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => fallback())
                    : fallback()));
  }

  @override
  Widget build(BuildContext context) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        logo('away'),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
                game['finished'] == true
                    ? '${game['score_away'] ?? '—'}–${game['score_home'] ?? '—'}'
                    : 'vs',
                style: const TextStyle(fontSize: 9))),
        logo('home'),
      ]));
}
