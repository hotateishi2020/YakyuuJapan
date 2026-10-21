import 'player_detail_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../widgets/baseball_loading.dart';

Future<Map<String, dynamic>>? _highSchoolCatalog;
Map<String, dynamic> _decodeHighSchoolCatalog(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

const highSchoolBlocks = [
  '北海道',
  '東北',
  '関東',
  '東京',
  '東海',
  '北信越',
  '近畿',
  '中国',
  '四国',
  '九州'
];

class HighSchoolRecordsBoard extends StatefulWidget {
  const HighSchoolRecordsBoard(
      {super.key,
      required this.year,
      this.scope,
      this.region,
      this.currentOnly = false});
  final int year;
  final String? scope;
  final String? region;
  final bool currentOnly;
  @override
  State<HighSchoolRecordsBoard> createState() => _HighSchoolRecordsBoardState();
}

class _HighSchoolRecordsBoardState extends State<HighSchoolRecordsBoard> {
  late final future = _highSchoolCatalog ??= rootBundle
      .loadString('backend/assets/data/high_school_records.json')
      .then((s) => compute(_decodeHighSchoolCatalog, s));
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('高校野球の記録を取得できませんでした'));
          }
          if (!snapshot.hasData) return const Center(child: BaseballLoading());
          final data = snapshot.data!;
          final records = (data['tournaments'] as List)
              .cast<Map<String, dynamic>>()
              .where((r) =>
                  (r['year'] as int) <= widget.year &&
                  (!widget.currentOnly || r['year'] == widget.year))
              .toList();
          if (widget.scope != null) {
            return _TournamentHistory(
                records: records,
                scope: widget.scope!,
                region: widget.region,
                coverage: '${data['coverage']}');
          }
          return DefaultTabController(
              length: 4,
              child: Column(children: [
                const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Colors.black,
                    tabs: [
                      Tab(text: '通算記録'),
                      Tab(text: '全国大会'),
                      Tab(text: 'ブロック大会'),
                      Tab(text: '地区大会')
                    ]),
                Expanded(
                    child: TabBarView(children: [
                  _CareerRecords(
                      records: records, data: data, year: widget.year),
                  _TournamentHistory(
                      records: records,
                      scope: 'national',
                      coverage: '${data['coverage']}'),
                  _TournamentHistory(
                      records: records,
                      scope: 'block',
                      coverage: '${data['coverage']}'),
                  _TournamentHistory(
                      records: records,
                      scope: 'district',
                      coverage: '${data['coverage']}'),
                ])),
              ]));
        },
      );
}

class _TournamentHistory extends StatefulWidget {
  const _TournamentHistory(
      {required this.records,
      required this.scope,
      required this.coverage,
      this.region});
  final List<Map<String, dynamic>> records;
  final String scope, coverage;
  final String? region;
  @override
  State<_TournamentHistory> createState() => _TournamentHistoryState();
}

class _TournamentHistoryState extends State<_TournamentHistory> {
  String? selectedRegion;
  String season = 'すべて';
  @override
  Widget build(BuildContext context) {
    final all =
        widget.records.where((r) => r['scope'] == widget.scope).toList();
    final regions = all.map((r) => '${r['region']}').toSet().toList()..sort();
    if (widget.scope == 'block') {
      regions.removeWhere(highSchoolBlocks.contains);
      regions.insertAll(0, highSchoolBlocks);
    }
    final region = widget.region ??
        (regions.contains(selectedRegion)
            ? selectedRegion
            : regions.firstOrNull);
    final rows = all
        .where((r) =>
            (widget.scope == 'national' || r['region'] == region) &&
            (season == 'すべて' || r['season'] == season))
        .toList()
      ..sort((a, b) {
        final cmp = (b['year'] as int).compareTo(a['year'] as int);
        return cmp != 0 ? cmp : '${a['season']}'.compareTo('${b['season']}');
      });
    const places = {
      '1': '優勝',
      '2': '準優勝',
      '4': 'ベスト4',
      '8': 'ベスト8',
      '16': 'ベスト16'
    };
    return Column(children: [
      Row(children: [
        if (widget.scope != 'national' &&
            widget.region == null &&
            regions.isNotEmpty)
          Expanded(
              child: DropdownButton<String>(
                  isExpanded: true,
                  value: region,
                  items: [
                    for (final r in regions)
                      DropdownMenuItem(value: r, child: Text(r))
                  ],
                  onChanged: (v) => setState(() => selectedRegion = v))),
        Expanded(
            child: DropdownButton<String>(
                isExpanded: true,
                value: season,
                items: [
                  for (final s in ['すべて', '春', '夏', '秋'])
                    DropdownMenuItem(
                        value: s, child: Text(s == 'すべて' ? '春夏秋すべて' : s))
                ],
                onChanged: (v) => setState(() => season = v!))),
      ]),
      Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('この条件の大会結果は未収録です。'))
              : SingleChildScrollView(
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        horizontalMargin: 8,
                        columnSpacing: 12,
                        headingRowHeight: 36,
                        dataRowMinHeight: 42,
                        dataRowMaxHeight: 180,
                        columns: [
                          const DataColumn(label: Text('年度・大会')),
                          for (final p in places.values)
                            DataColumn(label: Text(p))
                        ],
                        rows: [
                          for (final r in rows)
                            DataRow(cells: [
                              DataCell(Tooltip(
                                  message: '出典：${r['source']}',
                                  triggerMode: TooltipTriggerMode.tap,
                                  child: Text(
                                      '${r['year']}年 ${r['season']}\n${r['district_name'] ?? r['region']}'))),
                              for (final p in places.keys)
                                DataCell(SizedBox(
                                    width: 150,
                                    child: Text(
                                        ((r['places'] as Map)[p] as List? ?? [])
                                                .isEmpty
                                            ? '—'
                                            : ((r['places'] as Map)[p] as List)
                                                .join('\n'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: p == '1'
                                                ? FontWeight.bold
                                                : FontWeight.normal)))),
                            ])
                        ],
                      )))),
      Padding(
          padding: const EdgeInsets.all(6),
          child: Text('同じ順位の学校は同じセルに表示。— は未収録または該当校なし。\n${widget.coverage}',
              style: const TextStyle(fontSize: 10))),
    ]);
  }
}

/// Use historical names for display, and merge documented renamed championship schools.
String highSchoolChampionKey(String school, String prefecture) {
  school = school.replaceAll('ＰＬ', 'PL');
  if (school == '慶応普通部' && prefecture == '東京') return '慶応|神奈川';
  final aliases = <String, String>{
    '中京商|愛知': '中京大中京',
    '中京|愛知': '中京大中京',
    '平安|京都': '龍谷大平安',
    '平安中|京都': '龍谷大平安',
    '東邦商|愛知': '東邦',
    '広陵中|広島': '広陵',
    '松山中|愛媛': '松山東',
    '松山東|愛媛': '松山東',
    '広島商業|広島': '広島商',
    '和歌山中|和歌山': '桐蔭',
    '愛知一中|愛知': '旭丘',
    '京都二中|京都': '鳥羽',
    '第一神港商|兵庫': '神港',
    '神港商|兵庫': '神港',
    '法政二|神奈川': '法政二',
    '浪華商|大阪': '大体大浪商',
    '浪商|大阪': '大体大浪商',
    '小倉中|福岡': '小倉',
    '高松商業|香川': '高松商',
    '海南中|和歌山': '海南',
    '岐阜商|岐阜': '県岐阜商',
    '育英商|兵庫': '育英',
    '関西学院中|兵庫': '関西学院',
    '関西学院|兵庫': '関西学院',
  };
  return '${aliases['$school|$prefecture'] ?? school}|$prefecture';
}

List<Map<String, dynamic>> highSchoolChampionshipCounts(
    List<Map<String, dynamic>> records) {
  final counts = <String, Map<String, dynamic>>{};
  for (final r in records.where(
      (r) => r['scope'] == 'national' && ['春', '夏'].contains(r['season']))) {
    final winners = (r['places'] as Map)['1'] as List? ?? [];
    for (final winner in winners) {
      final name = winner == '松山東' && r['year'] == 1950 ? '松山商' : '$winner';
      final key = highSchoolChampionKey(name, '${r['champion_pref'] ?? ''}');
      final row = counts.putIfAbsent(
          key,
          () => {
                'school': key.split('|').first,
                'prefecture': key.split('|').last,
                '春': 0,
                '夏': 0,
                'total': 0
              });
      row[r['season']] = (row[r['season']] as int) + 1;
      row['total'] = (row['total'] as int) + 1;
    }
  }
  return counts.values.toList()
    ..sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
}

class _CareerRecords extends StatelessWidget {
  const _CareerRecords(
      {required this.records, required this.data, required this.year});
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> data;
  final int year;
  @override
  Widget build(BuildContext context) {
    final counts = highSchoolChampionshipCounts(records);
    final hrs = (data['home_runs'] as List).cast<Map<String, dynamic>>();
    final reported = (data['reported_home_runs'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((r) => (r['year'] as int) <= year)
        .toList();
    Widget grid(List<String> headings, List<List<String>> rows) =>
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(columnSpacing: 18, columns: [
              for (final h in headings) DataColumn(label: Text(h))
            ], rows: [
              for (final row in rows)
                DataRow(cells: [
                  for (var i = 0; i < row.length; i++)
                    DataCell(headings[i] == '選手'
                        ? PlayerNameLink(
                            player: {'name': row[i]}, child: Text(row[i]))
                        : Text(row[i]))
                ])
            ]));
    return ListView(children: [
      ListTile(
          title: Text('春夏の優勝回数（$year年まで）'),
          subtitle: const Text('春＝選抜、夏＝全国選手権。旧校名を統合して集計（1950年の松山東は松山商に含む）。')),
      grid([
        '学校',
        '都道府県',
        '春',
        '夏',
        '通算'
      ], [
        for (final r in counts)
          [
            '${r['school']}',
            '${r['prefecture']}',
            '${r['春']}',
            '${r['夏']}',
            '${r['total']}'
          ]
      ]),
      ListTile(
          title: const Text('甲子園・春夏通算本塁打'),
          subtitle: Text(
              '${data['through_year']}年までの上位${hrs.length}人。練習試合・地方大会の本塁打は含みません。')),
      grid([
        '順位',
        '選手',
        '学校',
        '本塁打'
      ], [
        for (var i = 0; i < hrs.length; i++)
          [
            '${hrs.indexWhere((r) => r['value'] == hrs[i]['value']) + 1}',
            '${hrs[i]['name']}',
            '${hrs[i]['school']}',
            '${hrs[i]['value']}'
          ]
      ]),
      const ListTile(
          title: Text('主な高校通算本塁打（練習試合を含む）'),
          subtitle: Text('報道による参考記録。公式戦のみの記録ではありません。')),
      grid([
        '選手',
        '学校',
        '本塁打',
        '最終年'
      ], [
        for (final r in reported)
          ['${r['name']}', '${r['school']}', '${r['value']}', '${r['year']}']
      ]),
      const Padding(
          padding: EdgeInsets.all(8),
          child: SelectableText(
              '出典：日刊スポーツ（2023/4/1）、デイリースポーツ（2023/8/8）。佐々木麟太郎は後日の140本に更新。',
              style: TextStyle(fontSize: 10))),
      const Padding(
          padding: EdgeInsets.all(8),
          child: SelectableText(
              '出典：高校野球データ検索システム https://www.hsbbdb.com/db/hsbbdb.html\n高校野球史 甲子園篇 https://data-man.com/kokoyakyu/ranking/individual/',
              style: TextStyle(fontSize: 10))),
    ]);
  }
}
