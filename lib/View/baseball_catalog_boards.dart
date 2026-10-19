import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
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

class StadiumsBoard extends StatelessWidget {
  const StadiumsBoard({super.key, required this.org});
  final String org;
  @override
  Widget build(BuildContext context) => CatalogData(
      path: '/baseball-catalog?section=stadiums&org=$org',
      builder: (data) {
        final rows = listMapFromJson(data['stadiums']);
        const fields = [
          'team',
          'image',
          'name',
          'category',
          'completed',
          'capacity',
          'construction',
          'maintenance',
          'revenue',
          'airport_distance',
          'station_distance'
        ];
        const labels = [
          'ホームチーム',
          '球場画像',
          '球場名',
          '球場カテゴリ',
          '完成日',
          '収容人数',
          '建設費',
          '維持管理費',
          '年間の興行収入',
          '最寄りの空港からの距離',
          '最寄りの駅からの距離'
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                      '未確認の項目は「未収録」。開場日と完成日、球団売上と球場収入は区別しています。空港は定期便のある空港が対象。直線距離は移動距離と異なります。',
                      style: TextStyle(fontSize: 11))),
              Expanded(
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: 1590,
                          child: Column(children: [
                            _stadiumRow([
                              for (final label in labels)
                                Text(label,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))
                            ], header: true),
                            Expanded(
                                child: ListView.builder(
                                    itemCount: rows.length,
                                    itemBuilder: (context, i) {
                                      final row = rows[i];
                                      return _stadiumRow([
                                        for (final field in fields)
                                          field == 'team'
                                              ? catalogLogo(row)
                                              : field == 'image' &&
                                                      '${row[field] ?? ''}'
                                                          .isNotEmpty
                                                  ? Image.asset('${row[field]}',
                                                      height: 82,
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (_, __,
                                                              ___) =>
                                                          const Text('画像未収録'))
                                                  : Text(
                                                      '${row[field] ?? '未収録'}',
                                                      style: const TextStyle(
                                                          fontSize: 12))
                                      ]);
                                    })),
                          ])))),
            ]);
      });
  Widget _stadiumRow(List<Widget> cells, {bool header = false}) => SizedBox(
      height: header ? 48 : 100,
      child: Row(children: [
        for (var i = 0; i < cells.length; i++)
          Container(
              width: i == 0
                  ? 90
                  : i == 1
                      ? 180
                      : i == 2
                          ? 240
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

final uniformNumbers = ['0', '00', for (var n = 1; n <= 300; n++) '$n'];
String uniformStatus(Map<String, dynamic> row) => switch (row['status']) {
      'active' => '現役',
      'retired' => '引退',
      'former' => 'NPB登録外（OB）',
      'permanent' => '永久欠番',
      'honored' => '事実上の永久欠番',
      _ => '現役状況未確認',
    };
Color uniformColor(Map<String, dynamic> row) => switch (row['status']) {
      'active' => const Color(0xffe0f2f1),
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
        final indexed = <String, List<Map<String, dynamic>>>{};
        for (final row in listMapFromJson(data['uniforms'])) {
          indexed
              .putIfAbsent('${row['id_team']}|${row['number']}', () => [])
              .add(row);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                  padding: const EdgeInsets.all(6),
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final status in [
                      'active',
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
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('${data['coverage'] ?? ''}',
                      style: const TextStyle(fontSize: 11))),
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
                                            itemCount: uniformNumbers.length,
                                            itemBuilder: (context, i) {
                                              final number = uniformNumbers[i];
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
    if (rows.isEmpty)
      return _numberCell(const Text('—', style: TextStyle(color: Colors.grey)));
    final latest = rows.first;
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
                          title: Text('${row['name']}'),
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
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                  child: TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: details,
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
  @override
  Widget build(BuildContext context) => CatalogData(
      path: '/baseball-catalog?section=hall&org=$org&year=$year',
      builder: (data) => ListView(children: [
            for (final section in [
              ('hall', '殿堂入り'),
              ('members', '名球会会員'),
              ('candidates', '名球会の基準達成候補（推定所要シーズン順）')
            ]) ...[
              Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(10),
                  child: Text(section.$2,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold))),
              if (section.$1 == 'candidates')
                const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                        '2000安打・200勝・250セーブ。残り記録 ÷ 選択年度の実績で比較（単純推計）。殿堂入りは投票によるため到達予測は行いません。',
                        style: TextStyle(fontSize: 12))),
              if (listMapFromJson(data[section.$1]).isEmpty)
                const ListTile(title: Text('該当する登録データがありません')),
              for (final row in listMapFromJson(data[section.$1]))
                ListTile(
                    dense: true,
                    title: Text('${row['name']}'),
                    subtitle: Text(section.$1 == 'candidates'
                        ? '${row['label']} ${row['value']} / ${row['target']}　残り${row['remaining']}　${row['estimate'] == null ? '予測不可（当年実績なし）' : '約${(row['estimate'] as num).toStringAsFixed(1)}シーズン'}'
                        : [
                            if (row['year'] != null) '${row['year']}年',
                            if (row['category'] != null) '${row['category']}'
                          ].join('・'))),
            ],
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${data['note'] ?? ''}',
                    style: const TextStyle(fontSize: 11))),
          ]));
}
