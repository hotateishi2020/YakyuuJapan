import 'pinned_horizontal_row.dart';
import 'player_detail_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../logic/stadium_location.dart';
import '../widgets/baseball_loading.dart';
import 'GamesBoard.dart' show teamLogoVisual;

class CatalogData extends StatefulWidget {
  const CatalogData({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(Map<String, dynamic>) builder;
  @override
  State<CatalogData> createState() => _CatalogDataState();
}

class _CatalogDataState extends State<CatalogData> {
  Map<String, dynamic>? data;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CatalogData old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) load();
  }

  Future<void> load() async {
    final id = ++request;
    setState(() {
      data = null;
      failed = false;
    });
    try {
      final response = await http
          .get(Env.api(widget.path))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) throw const FormatException('取得失敗');
      final value =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (mounted && request == id) setState(() => data = value);
    } catch (_) {
      if (mounted && request == id) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => failed
      ? Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('情報を取得できませんでした'),
          TextButton(onPressed: load, child: const Text('再読み込み')),
        ]))
      : data == null
          ? const Center(child: BaseballLoading())
          : widget.builder(data!);
}

Widget catalogLogo(Map<String, dynamic> team) {
  final name = '${team['name_team'] ?? team['team'] ?? ''}';
  final visual = teamLogoVisual(name,
      abbrev: '${team['abbrev'] ?? team['name_shortest'] ?? ''}',
      mlb: team['org'] == 'mlb');
  Widget fallback() => Text(name, style: const TextStyle(fontSize: 11));
  return Tooltip(
      message: name,
      child: SizedBox(
          width: 54,
          height: 34,
          child: visual.asset != null
              ? Image.asset(visual.asset!,
                  fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback())
              : visual.networkUrl != null
                  ? Image.network(visual.networkUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => fallback())
                  : fallback()));
}

// Sort the numeric value, not the formatted Japanese display string.
(double, String)? stadiumSortValue(dynamic raw, String field) {
  final text = '${raw ?? ''}'.replaceAll(',', '');
  if (field == 'completed') {
    final date = RegExp(r'(\d{4})年(?:(\d+)月)?(?:(\d+)日)?').firstMatch(text);
    if (date == null) return null;
    return (
      double.parse(date[1]!) * 10000 +
          (double.tryParse(date[2] ?? '') ?? 0) * 100 +
          (double.tryParse(date[3] ?? '') ?? 0),
      'date'
    );
  }
  if (field.endsWith('_distance')) {
    final distance = RegExp(r'(\d+(?:\.\d+)?)\s*(km|m|分)').firstMatch(text);
    if (distance == null) return null;
    return (
      double.parse(distance[1]!) * (distance[2] == 'm' ? .001 : 1),
      distance[2] == '分' ? 'time' : 'distance'
    );
  }
  final matches = RegExp(r'(\d+(?:\.\d+)?)\s*(億|万|千)?').allMatches(text);
  if (matches.isEmpty) return null;
  double value = 0;
  // Parenthetical notes contain years and must not become part of the amount.
  final amount = text.split(RegExp(r'[（(／/]')).first;
  for (final match
      in RegExp(r'(\d+(?:\.\d+)?)\s*(億|万|千)?').allMatches(amount)) {
    value += double.parse(match[1]!) *
        switch (match[2]) {
          '億' => 100000000,
          '万' => 10000,
          '千' => 1000,
          _ => 1
        };
  }
  return (value, text.contains('ドル') ? 'USD' : 'number');
}

int compareStadiumRows(Map<String, dynamic> a, Map<String, dynamic> b,
    String? field, bool ascending) {
  int teamOrder() {
    final league = ((a['id_league'] as num?)?.toInt() ?? 999)
        .compareTo((b['id_league'] as num?)?.toInt() ?? 999);
    return league != 0
        ? league
        : ((a['id_team'] as num?)?.toInt() ?? 999)
            .compareTo((b['id_team'] as num?)?.toInt() ?? 999);
  }

  if (field == null) return teamOrder();
  if (field == 'team') return teamOrder() * (ascending ? 1 : -1);
  final av = stadiumSortValue(a[field], field),
      bv = stadiumSortValue(b[field], field);
  if (av == null || bv == null) {
    return av == null && bv == null
        ? teamOrder()
        : av == null
            ? 1
            : -1;
  }
  // Keep currencies and walking times separate instead of inventing conversions.
  final unit = av.$2.compareTo(bv.$2);
  if (unit != 0) return unit;
  final value = av.$1.compareTo(bv.$1) * (ascending ? 1 : -1);
  return value == 0 ? teamOrder() : value;
}

class StadiumsBoard extends StatefulWidget {
  const StadiumsBoard({super.key, required this.org});
  final String org;
  @override
  State<StadiumsBoard> createState() => _StadiumsBoardState();
}

class _StadiumsBoardState extends State<StadiumsBoard> {
  final _horizontal = ScrollController();
  @override
  void dispose() { _horizontal.dispose(); super.dispose(); }
  String? sortField;
  String stadiumLevel = 'first';
  bool ascending = true;
  @override
  Widget build(BuildContext context) => CatalogData(
      path: '/baseball-catalog?section=stadiums&org=${widget.org}',
      builder: (data) {
        final rows = listMapFromJson(data['stadiums'])
            .map((row) => {...row, 'address': stadiumLocation(row['address'])})
            .where((r) =>
                stadiumLevel == 'all' ||
                (r['stadium_level'] ?? 'first') == stadiumLevel)
            .toList()
          ..sort((a, b) => compareStadiumRows(a, b, sortField, ascending));
        final showDimensions = stadiumLevel == 'first' || stadiumLevel == 'all';
        final fields = [
          'name',
          'team',
          'image_outside',
          'image',
          'category',
          'address',
          'completed',
          'capacity',
          if (showDimensions) ...['outfield_distance', 'fence_height'],
          'construction',
          'maintenance',
          'revenue',
          'airport_distance',
          'station_distance'
        ];
        final labels = [
          '球場名',
          'ホームチーム',
          '外観',
          '内観',
          '球場カテゴリ',
          '所在地',
          '完成日',
          '収容人数',
          if (showDimensions) ...['スタンドまでの距離', '外野フェンスの高さ'],
          '建設費',
          '維持管理費',
          '年間の興行収入',
          '最寄りの空港からの距離',
          '最寄り駅・距離／徒歩目安'
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final entry in const {
                      'first': '1軍球場',
                      'farm': '2軍球場',
                      'regional': '地方球場',
                      'all': 'すべて'
                    }.entries)
                      Padding(
                          padding: const EdgeInsets.all(3),
                          child: ChoiceChip(
                              label: Text(entry.value),
                              selected: stadiumLevel == entry.key,
                              onSelected: (_) =>
                                  setState(() => stadiumLevel = entry.key))),
                  ])),
              Expanded(
                  child: SingleChildScrollView(
                      key: const ValueKey('stadium-grid-scroll'),
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: 1905 + (showDimensions ? 360 : 0),
                          child: Column(children: [
                            _stadiumRow([
                              for (var i = 0; i < labels.length; i++)
                                InkWell(
                                  key: ValueKey('stadium-sort-${fields[i]}'),
                                  onTap: (['name', 'image_outside', 'image', 'category'].contains(fields[i]) ||
                                          ['outfield_distance', 'fence_height']
                                              .contains(fields[i]))
                                      ? null
                                      : () => setState(() {
                                            ascending = sortField == fields[i]
                                                ? !ascending
                                                : true;
                                            sortField = fields[i];
                                          }),
                                  child: SizedBox.expand(
                                      child: Center(
                                          child: Text(
                                    '${labels[i]}${(['name', 'image_outside', 'image', 'category'].contains(fields[i]) || [
                                          'outfield_distance',
                                          'fence_height'
                                        ].contains(fields[i])) ? '' : sortField == fields[i] ? ascending ? ' ▲' : ' ▼' : ' ↕'}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ))),
                                ),
                            ], header: true),
                            Expanded(
                                child: ListView.builder(
                                    itemCount: rows.length + 1,
                                    itemBuilder: (context, i) {
                                      if (i == rows.length) {
                                        return const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Text(
                                        '距離は本塁から左翼・中堅・右翼の外野フェンスまで。フェンス高は外野のもので、内野の防球ネットとは区別しています。完成日は新築時の完成年月（確認できた精度）で表示し、竣工式の場合は明記しています。未確認の項目は「未収録」。開場日と完成日、球団売上と球場収入は区別しています。空港は定期便のある空港が対象。直線距離は移動距離と異なります。見出しで昇順・降順を切り替えます（未収録は末尾、距離と徒歩時間・通貨は別々に比較）。',
                                        style: TextStyle(fontSize: 11)));
                                      }
                                      final row = rows[i];
                                      return _stadiumRow([
                                        for (final field in fields)
                                          field == 'team'
                                              ? catalogLogo(row)
                                              : (field == 'image' ||
                                                          field ==
                                                              'image_outside') &&
                                                      '${row[field] ?? ''}'
                                                          .isNotEmpty
                                                  ? Column(
                                                      mainAxisSize: MainAxisSize
                                                          .min,
                                                      children: [
                                                          Flexible(
                                                              child: Image.asset(
                                                                  '${row[field]}',
                                                                  cacheWidth:
                                                                      360,
                                                                  height:
                                                                      row['image_generated'] ==
                                                                              true
                                                                          ? 64
                                                                          : 82,
                                                                  fit: BoxFit
                                                                      .contain,
                                                                  errorBuilder: (_,
                                                                          __,
                                                                          ___) =>
                                                                      const Text(
                                                                          '画像未収録'))),
                                                        ])
                                                  : Tooltip(
                                                      message:
                                                          '${row['${field}_source'] ?? ''}',
                                                      child: Text(
                                                          '${row[field] ?? '未収録'}',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      12)))
                                      ]);
                                    })),
                          ])))),
            ]);
      });
  Widget _stadiumRow(List<Widget> cells, {bool header = false}) => SizedBox(
      height: header ? 48 : 100,
      child: PinnedHorizontalRow(controller: _horizontal, pinnedWidth: 240, minHeight: header ? 48 : 100, children: [
        for (var i = 0; i < cells.length; i++)
          Container(
              width: i == 0
                  ? 240
                  : i == 2 || i == 3
                      ? 180
                      : i == 1
                          ? 90
                          : (stadiumLevel == 'first' ||
                                      stadiumLevel == 'all') &&
                                  (i == 8 || i == 9)
                              ? 180
                              : 135,
              height: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: header ? Colors.black87 : Colors.white,
                  border: Border.all(color: Colors.black26, width: .5)),
              child: cells[i]),
      ]));
}

final uniformNumbers = ['0', '00', for (var n = 1; n <= 250; n++) '$n'];
String uniformDisplayStatus(Map<String, dynamic> row) =>
    row['status'] == 'active' && row['worn_in_selected_year'] == false
        ? 'active_past'
        : '${row['status']}';
String uniformStatus(Map<String, dynamic> row) =>
    switch (uniformDisplayStatus(row)) {
      'active' => '現役（当年着用）',
      'active_past' => '現役（当年未着用）',
      'retired' => '引退',
      'former' => 'NPB登録外（OB）',
      'permanent' => '永久欠番',
      'honored' => '事実上の永久欠番',
      _ => '現役状況未確認',
    };
Color uniformColor(Map<String, dynamic> row) =>
    switch (uniformDisplayStatus(row)) {
      'active' => const Color(0xffe0f2f1),
      'active_past' => const Color(0xffdbeafe),
      'retired' || 'former' => const Color(0xffeeeeee),
      'permanent' => const Color(0xffffdf80),
      'honored' => const Color(0xffe1bee7),
      _ => Colors.white,
    };

class UniformHistoryBoard extends StatelessWidget {
  const UniformHistoryBoard({super.key, required this.org, required this.year});
  final String org;
  final int year;
  @override
  Widget build(BuildContext context) => CatalogData(
      path: '/baseball-catalog?section=uniforms&org=$org&year=$year',
      builder: (data) {
        final teams = listMapFromJson(data['teams']);
        final numbers = {
          ...uniformNumbers,
          for (final row in listMapFromJson(data['uniforms']))
            if ((int.tryParse('${row['number']}') ?? 0) <= 250 ||
                (int.tryParse('${row['number']}') ?? 0) > 300)
              '${row['number']}'
        }.toList()
          ..sort((a, b) {
            int group(String number) => RegExp(r'^0[0-9]{2}$').hasMatch(number)
                ? 1
                : (int.tryParse(number) ?? 0) <= 250
                    ? 0
                    : 2;
            final category = group(a).compareTo(group(b));
            if (category != 0) return category;
            final numeric =
                (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0);
            return numeric != 0 ? numeric : a.length.compareTo(b.length);
          });
        final indexed = <String, List<Map<String, dynamic>>>{};
        for (final row in listMapFromJson(data['uniforms'])) {
          indexed
              .putIfAbsent('${row['id_team']}|${row['number']}', () => [])
              .add(row);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                          child: SizedBox(
                              height: (teams.length + 1) * 54,
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                        width: 76,
                                        child: Column(children: [
                                          _numberCell(
                                              const Text('球団',
                                                  style: TextStyle(
                                                      color: Colors.white)),
                                              color: Colors.black87,
                                              width: 76),
                                          for (final team in teams)
                                            _numberCell(catalogLogo(team),
                                                width: 76,
                                                color: parseColorNameOrNull(
                                                        '${team['color_back']}')
                                                    ?.withValues(alpha: .12)),
                                        ])),
                                    Expanded(
                                        child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            itemExtent: 94,
                                            itemCount: numbers.length,
                                            itemBuilder: (context, i) {
                                              final number = numbers[i];
                                              return Column(children: [
                                                _numberCell(
                                                    Text(number,
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.white)),
                                                    color: Colors.black87),
                                                for (final team in teams)
                                                  _uniformCell(
                                                      context,
                                                      team,
                                                      number,
                                                      indexed['${team['id_team']}|$number'] ??
                                                          []),
                                              ]);
                                            })),
                                  ]))))),
              Padding(
                  padding: const EdgeInsets.all(6),
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final status in [
                      'active',
                      'active_past',
                      'retired',
                      'permanent',
                      'honored',
                      'former',
                      'unknown'
                    ])
                      Container(
                          color: uniformColor({'status': status}),
                          padding: const EdgeInsets.all(4),
                          child: Text(uniformStatus({'status': status}),
                              style: const TextStyle(fontSize: 11))),
                  ])),
            ]);
      });
  Widget _numberCell(Widget child, {Color? color, double width = 94}) =>
      Container(
          width: width,
          height: 54,
          decoration: BoxDecoration(
              color: color ?? Colors.white,
              border: Border.all(color: Colors.black26, width: .5)),
          alignment: Alignment.center,
          child: child);
  Widget _uniformCell(BuildContext context, Map<String, dynamic> team,
      String number, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return _numberCell(const Text('—', style: TextStyle(color: Colors.grey)));
    }
    final latest = rows.first;
    final scope = PlayerDetailScope.of(context);
    void details() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('${team['name_team']} #$number'),
              content: SizedBox(
                  width: 360,
                  child: ListView(shrinkWrap: true, children: [
                    for (final row in rows)
                      ListTile(
                          dense: true,
                          title: PlayerNameLink(player: {
                            ...row,
                            if (scope != null) 'org': scope.org,
                            if (scope != null) 'int_year': scope.year
                          }, child: Text('${row['name']}')),
                          subtitle: Text(
                              '${row['period'] ?? ''}　${uniformStatus(row)}')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('閉じる'))
              ],
            ));
    return _numberCell(
        Tooltip(
            message:
                '${latest['name']}・${uniformStatus(latest)}${latest['number_status'] == null ? '' : '・${uniformStatus({
                        'status': latest['number_status']
                      })}'}',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (latest['new_uniform_number'] == true)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(3)),
                  child: const Text('新背番号',
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(
                    child: TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => showPlayerDetail(
                            context, {...latest, 'id_team': team['id_team']}),
                        child: Text('${latest['surname'] ?? latest['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black)))),
                if (rows.length > 1)
                  InkWell(
                      key: ValueKey('uniform-more-${team['id_team']}-$number'),
                      onTap: details,
                      child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Text('+${rows.length - 1}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold)))),
              ]),
            ])),
        color: uniformColor({
          ...latest,
          if (latest['number_status'] != null) 'status': latest['number_status']
        }));
  }
}

class HallOfFameBoard extends StatelessWidget {
  const HallOfFameBoard({super.key, required this.org, required this.year});
  final String org;
  final int year;
  // Source names may include typography footnotes; keep them out of cards.
  static String _displayName(dynamic value) =>
      '${value ?? ''}'.replaceAll(RegExp(r'【\s*※[^】]*】'), '').trim();
  @override
  Widget build(BuildContext context) => CatalogData(
      path: '/baseball-catalog?section=hall&org=$org&year=$year',
      builder: (data) {
        String normalizedName(dynamic value) => _displayName(value)
            .replaceAll(RegExp(r'[\s　・･.]'), '')
            .replaceAll('髙', '高')
            .replaceAll('﨑', '崎');
        final members = listMapFromJson(data['members'])
            .map((row) => normalizedName(row['name']))
            .where((name) => name.isNotEmpty)
            .toSet();
        List<Map<String, dynamic>> sectionRows(String key) {
          final rows = listMapFromJson(data[key])
              .where((row) =>
                  key != 'candidates' ||
                  !members.contains(normalizedName(row['name'])))
              .toList();
          if (key == 'candidates') return rows;
          int dateKey(Map<String, dynamic> row) {
            final raw = row['joined_date'] ??
                row['membership_sort_date'] ??
                row['inducted_date'] ??
                row['year'];
            final parts = RegExp(r'\d+')
                .allMatches('${raw ?? ''}')
                .map((m) => int.parse(m[0]!))
                .toList();
            if (parts.isEmpty) return 99999999;
            return parts[0] * 10000 +
                (parts.length > 1 ? parts[1] : 1) * 100 +
                (parts.length > 2 ? parts[2] : 1);
          }

          final original = {for (var i = 0; i < rows.length; i++) rows[i]: i};
          rows.sort((a, b) {
            final order = dateKey(a).compareTo(dateKey(b));
            return order != 0 ? order : original[a]!.compareTo(original[b]!);
          });
          return rows;
        }

        return ListView(children: [
          for (final section in [
            ('hall', '殿堂入り'),
            ('members', '名球会会員'),
            ('candidates', '名球会の基準達成候補（達成割合順）')
          ])
            ExpansionTile(
              key: ValueKey('hall-section-$org-$year-${section.$1}'),
              initiallyExpanded: section.$1 == 'candidates',
              backgroundColor: Colors.black87,
              collapsedBackgroundColor: Colors.black87,
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
              title: Text(section.$2,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              children: [ColoredBox(color: Colors.white,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (section.$1 == 'candidates')
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                            '2000安打・200勝・250セーブ。各基準に対する通算記録の達成割合で比較。殿堂入りは投票によるため到達予測は行いません。',
                            style: TextStyle(fontSize: 12))),
                  if (sectionRows(section.$1).isEmpty)
                    const ListTile(title: Text('該当する登録データがありません')),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: LayoutBuilder(builder: (context, constraints) {
                      const gap = 6.0;
                      final columns =
                          ((constraints.maxWidth + gap) / 180).floor().clamp(1, 1000);
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) / columns;
                      final rows = sectionRows(section.$1);
                      return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              SizedBox(
                                key: ValueKey('hall-card-${section.$1}-$i'),
                                width: width,
                                child: _playerCard(rows[i],
                                    candidate: section.$1 == 'candidates'),
                              ),
                          ]);
                    }),
                  ),
                ])),
              ],
            ),
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${data['note'] ?? ''}',
                  style: const TextStyle(fontSize: 11))),
        ]);
      });

  Widget _playerCard(Map<String, dynamic> row, {required bool candidate}) {
    final value = num.tryParse('${row['value']}') ?? 0;
    final target = num.tryParse('${row['target']}') ?? 0;
    final overTarget = candidate && target > 0 && value > target;
    final nearTarget = candidate && target > 0 && value / target >= 0.9;
    final detail = candidate
        ? '${row['label']} ${row['value']} / ${row['target']}\n達成${((num.tryParse('${row['value']}') ?? 0) / (num.tryParse('${row['target']}') ?? 1) * 100).toStringAsFixed(1)}%　残り${row['remaining']}　${row['estimate'] == null ? '予測不可（当年実績なし）' : '約${(row['estimate'] as num).toStringAsFixed(1)}シーズン'}'
        : [
            if (row['year'] != null) '${row['year']}年',
            if (row['category'] != null) '${row['category']}'
          ].join('・');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: overTarget
            ? Colors.orange.shade100
            : nearTarget
                ? Colors.yellow.shade100
                : Colors.white,
        border: Border.all(color: Colors.black26, width: .5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlayerNameLink(
                player: {...row, 'name': _displayName(row['name'])},
                child: Text(_displayName(row['name']),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87))),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(detail,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ]),
    );
  }
}
