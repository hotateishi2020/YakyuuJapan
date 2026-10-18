import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tools/json_utils.dart';
import '../logic/strength_usage.dart';
import '../tools/color_parse.dart';
import 'achievement_badge.dart';
import 'achievement_layout.dart';
import '../logic/achievement_priority.dart';
import '../logic/player_honors.dart';

void showStrengthSource(BuildContext context, String title, String detail, List<String> urls) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(detail),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]));

class StrengthDraft extends StatefulWidget {
  const StrengthDraft({super.key, required this.year});
  final int year;
  @override
  State<StrengthDraft> createState() => _StrengthDraftState();
}

class _StrengthDraftState extends State<StrengthDraft> {
  late Future<Map<String, dynamic>> _data;
  final _horizontal = ScrollController();
  final _header = ScrollController();
  final _vertical = ScrollController();
  Future<Map<String, dynamic>> load() async => Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('backend/assets/data/draft_${widget.year}.json')) as Map);

  void _syncHeader() {
    if (_header.hasClients && _horizontal.hasClients) {
      _header.jumpTo(_horizontal.offset.clamp(0.0, _header.position.maxScrollExtent));
    }
  }

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_syncHeader);
    _data = load();
  }

  @override
  void didUpdateWidget(covariant StrengthDraft old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) {
      _data = load();
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _header.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _showPrediction(Map<String, dynamic> prediction) {
    final evidence = [prediction, ...listMapFromJson(prediction['additional_sources'])];
    showStrengthSource(
        context,
        '${prediction['player']}・${prediction['team']}',
        '${evidence.map((e) => [
              '${e['status'] ?? '指名予想'}',
              '${e['reason']}',
            ].join('\n')).join('\n\n')}\n\n各公表時点の予想であり、指名・獲得確定ではありません。',
        <String>{
          for (final e in evidence) ...[if (e['source_url'] != null) '${e['source_url']}', if (e['verification_url'] != null) '${e['verification_url']}']
        }.toList());
  }

  Color _positionColor(String position) {
    final base = position.contains('投手')
        ? const Color(0xFFEF5350)
        : position.contains('捕手')
            ? const Color(0xFF2196F3)
            : RegExp('内野|一塁|二塁|三塁|遊撃').hasMatch(position)
                ? const Color(0xFFFFD54F)
                : RegExp('外野|左翼|中堅|右翼').hasMatch(position)
                    ? const Color(0xFF43A047)
                    : position.contains('指名')
                        ? const Color(0xFF9C27B0)
                        : Colors.grey;
    return Color.lerp(base, Colors.white, .88)!;
  }

  Color _categoryColor(String category) => switch (category) {
        '高校生' => Colors.red.shade700,
        '大学生' => Colors.blue.shade700,
        '社会人' => Colors.green.shade700,
        _ => Colors.orange.shade800,
      };

  String _careerText(Map<String, dynamic> player) => draftCareerText(player);

  List<String> _values(Map<String, dynamic> p) => [
        '${p['attention_grade'] ?? '—'}',
        '${p['name'] ?? ''}',
        '${p['category'] == '独立リーグ' ? '独立' : p['category']}',
        '${p['team'] ?? ''}',
        draftAgeOnMarch31(p['date_birth'], widget.year + 1)?.toString() ?? '—',
        p['height'] == null ? '—' : '${p['height']}cm',
        p['weight'] == null ? '—' : '${p['weight']}kg',
        '${p['hand'] ?? ''}',
        '${p['position'] ?? ''}',
        _careerText(p),
        '${p['features'] ?? ''}',
        '',
      ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => FutureBuilder<Map<String, dynamic>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('${widget.year}年のドラフト候補はまだ登録されていません。'));
              }
              if (!snapshot.hasData) {
                return const Center(child: BaseballLoading());
              }
              final data = snapshot.data!;
              final players = listMapFromJson(data['players']).indexed.toList()
                ..sort((a, b) {
                  final gradeOrder = draftAttentionRank(a.$2).compareTo(draftAttentionRank(b.$2));
                  if (gradeOrder != 0) return gradeOrder;
                  const order = {'高校生': 0, '大学生': 1, '社会人': 2, '独立リーグ': 3};
                  final result = (order[a.$2['category']] ?? 4).compareTo(order[b.$2['category']] ?? 4);
                  return result == 0 ? a.$1.compareTo(b.$1) : result;
                });
              const headers = ['注目度', '選手名', '所属', 'チーム', '年齢', '身長', '体重', '投打', 'ポジション', '経歴', '特徴', '獲得予想', '特集動画'];
              const minimumWidths = [42.0, 72.0, 50.0, 100.0, 42.0, 52.0, 50.0, 76.0, 68.0, 180.0, 180.0, 140.0, 180.0];
              final minimumWidth = minimumWidths.reduce((a, b) => a + b);
              final scale = constraints.maxWidth > minimumWidth ? constraints.maxWidth / minimumWidth : 1.0;
              final widths = [for (final width in minimumWidths) width * scale];
              final logosPerRow = ((widths[11] - 12 + 2) / 38).floor().clamp(1, 12);
              const style = TextStyle(inherit: false, fontSize: 12, height: 1.4, color: Colors.black87);
              double textHeight(String text, double width, int column) {
                // Match the rendered font and the space inside padding + border.
                final painter = TextPainter(text: TextSpan(text: text,
                    style: style.copyWith(fontWeight: column <= 2 ? FontWeight.bold : FontWeight.normal)),
                    textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
                  ..layout(maxWidth: width - 13);
                final height = painter.height;
                painter.dispose();
                return height.ceilToDouble() + 14;
              }

              final heights = [
                for (final p in players)
                  [
                    if (draftTopVideo(p.$2) != null) 94.0 + textHeight('${draftTopVideo(p.$2)!['view_count']}回再生', widths[12], 12) else 48.0,
                    for (var i = 0; i < 11; i++) textHeight(_values(p.$2)[i], widths[i], i),
                    ((listMapFromJson(p.$2['predictions']).length / logosPerRow).ceil() * 38 + 12).toDouble(),
                  ].reduce((a, b) => a > b ? a : b)
              ];
              Widget cell(int index, double height, {Map<String, dynamic>? player}) {
                Widget child;
                if (player == null) {
                  child = Text(headers[index], style: style.copyWith(fontWeight: FontWeight.bold));
                  if (index == 4) {
                    child = Tooltip(message: '${widget.year + 1}年3月31日時点', child: child);
                  }
                } else if (index == 12) {
                  final video = draftTopVideo(player);
                  child = video == null ? Text(player['feature_video_checked_at'] == null ? '未取得' : '—', style: style) : Tooltip(
                    message: '${video['title']}\n${video['view_count']}回再生（取得時点）',
                    child: InkWell(
                      key: ValueKey('draft-video-${player['name']}'),
                      onTap: () async {
                        final uri = Uri.https('www.youtube.com', '/watch', {'v': '${video['video_id']}'});
                        var opened = false;
                        try { opened = await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'); } catch (_) {}
                        if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('動画を開けませんでした。')));
                      },
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: SizedBox(height: 94, width: 168, child: Stack(fit: StackFit.expand, children: [
                          Image.network('https://i.ytimg.com/vi/${video['video_id']}/hqdefault.jpg', fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12)),
                          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32)),
                        ]))),
                        Text('${video['view_count']}回再生', maxLines: 1, style: const TextStyle(inherit: false, color: Colors.black87, height: 1.4, fontSize: 11)),
                      ]),
                    ),
                  );
                } else if (index == 11) {
                  child = Wrap(spacing: 2, runSpacing: 2, children: [
                    for (final prediction in listMapFromJson(player['predictions']))
                      Tooltip(
                        message: '${prediction['team']}：${prediction['status'] ?? '指名予想'}',
                        child: InkWell(
                          key: ValueKey('draft-prediction-${player['name']}-${prediction['team']}'),
                          onTap: () => _showPrediction({...prediction, 'player': player['name']}),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Image.asset('${prediction['logo_asset']}',
                                semanticLabel: '${prediction['team']}', errorBuilder: (_, __, ___) => Center(child: Text('${prediction['team']}', style: style))),
                          ),
                        ),
                      ),
                  ]);
                } else {
                  child = Text(_values(player)[index],
                      style: style.copyWith(
                        color: index == 2 ? _categoryColor('${player['category']}') : null,
                        fontWeight: index <= 2 ? FontWeight.bold : FontWeight.normal,
                      ));
                  if (index == 1) {
                    child = InkWell(
                        onTap: () => showStrengthSource(
                            context, '${player['name']}', "確認日：${data['checked_at']}\n${_careerText(player)}\n${player['features']}", (player['sources'] as List).cast<String>()),
                        child: child);
                  }
                }
                if (index == 0 && player != null) {
                  child = Tooltip(
                      message: '${draftAttentionLabels[player['attention_grade']] ?? '未評価'}\n${player['attention_reason'] ?? ''}',
                      child: InkWell(
                          onTap: () => showStrengthSource(
                                  context,
                                  '${player['name']} 注目度 ${player['attention_grade']}',
                                  '${draftAttentionLabels[player['attention_grade']] ?? '未評価'}\nアプリ独自の予想評価（${player['attention_as_of'] ?? ''}）\n${player['attention_reason'] ?? ''}\n\n${listMapFromJson(player['attention_sources']).map((e) => '${e['reason']}').join('\n\n')}',
                                  [
                                    for (final e in listMapFromJson(player['attention_sources'])) '${e['source_url']}',
                                    if (player['attention_source'] != null) '${player['attention_source']}'
                                  ]),
                          child: Center(child: Text('${player['attention_grade'] ?? '—'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))));
                }
                if (index >= 4 && index <= 8) {
                  child = FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
                }
                return Container(
                  key: player == null ? null : ValueKey('draft-cell-${player['name']}-$index'),
                  width: widths[index],
                  height: height,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                      color: player == null ? Colors.grey.shade200 : _positionColor('${player['position']}'), border: Border.all(color: Colors.grey.shade400, width: .5)),
                  child: child,
                );
              }

              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.all(8), child: Text('${widget.year}年 NPBドラフト注目選手（計${players.length}人）', style: const TextStyle(fontWeight: FontWeight.bold)))),
                ]),
                Row(children: [
                  for (var i = 0; i < 4; i++) cell(i, 40),
                  Expanded(
                      child: SingleChildScrollView(
                          controller: _header,
                          physics: const NeverScrollableScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [for (var i = 4; i < headers.length; i++) cell(i, 40)]))),
                ]),
                Expanded(
                    child: SingleChildScrollView(
                  key: const ValueKey('draft-grid-scroll'),
                  controller: _vertical,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Column(children: [
                        for (var row = 0; row < players.length; row++) Row(children: [for (var col = 0; col < 4; col++) cell(col, heights[row], player: players[row].$2)])
                      ]),
                      Expanded(
                          child: Scrollbar(
                        controller: _horizontal,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          key: const ValueKey('draft-horizontal-scroll'),
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: Column(children: [
                            for (var row = 0; row < players.length; row++)
                              Row(children: [for (var col = 4; col < headers.length; col++) cell(col, heights[row], player: players[row].$2)])
                          ]),
                        ),
                      )),
                    ]),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                            "確認日：${data['checked_at']}。年齢は${widget.year + 1}年3月31日時点（生年月日未確認は—）。選手名で詳細、球団ロゴで指名予想の根拠を表示。注目度はアプリ予想（タップで基準と根拠）。S競合必至／A競合の可能性／Bドラ1候補／C上位候補／D指名候補／E育成候補。ロゴなしは予想根拠未確認。特集動画は取得した通常動画の中で再生数最多の1件（タップで再生）。指名・獲得確定ではありません。",
                            style: const TextStyle(fontSize: 11, color: Colors.black54))),
                  ]),
                )),
              ]);
            },
          ));
}

Map<String, dynamic>? draftTopVideo(Map<String, dynamic> player) {
  final videos = listMapFromJson(player['feature_videos']).where((v) =>
    RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch('${v['video_id']}') && v['view_count'] is num && v['is_short'] != true).toList()
    ..sort((a,b) => (b['view_count'] as num).compareTo(a['view_count'] as num));
  return videos.isEmpty ? null : videos.first;
}

String draftCareerText(Map<String, dynamic> player) {
  final entries = <Map<String, dynamic>>[
    if ('${player['achievement'] ?? ''}'.trim().isNotEmpty)
      {'label': '${player['achievement']}'},
    ...listMapFromJson(player['career_facts']),
  ].indexed.toList();
  int year(Map<String, dynamic> fact) => int.tryParse('${fact['year']}') ??
      int.tryParse(RegExp(r'(?:19|20)\d{2}').firstMatch('${fact['label']}')?.group(0) ?? '') ?? 0;
  int season(Map<String, dynamic> fact) {
    final text = '${fact['season'] ?? fact['label'] ?? ''}';
    if (text.contains('春')) return 1;
    if (text.contains('夏')) return 2;
    if (text.contains('秋')) return 3;
    if (text.contains('冬')) return 4;
    return 0;
  }
  entries.sort((a, b) {
    final byYear = year(b.$2).compareTo(year(a.$2));
    if (byYear != 0) return byYear;
    final bySeason = season(b.$2).compareTo(season(a.$2));
    return bySeason != 0 ? bySeason : a.$1.compareTo(b.$1);
  });
  return entries.map((entry) {
    final fact = entry.$2;
    final label = '${fact['label'] ?? ''}';
    final school = '${fact['school'] ?? ''}'.trim();
    if (fact['kind'] == 'koshien' && school.isNotEmpty && !label.contains(school)) {
      return label.replaceFirst('甲子園', '甲子園（$school）');
    }
    return label;
  }).where((label) => label.isNotEmpty).join('\n');
}

int? draftAgeOnMarch31(dynamic rawBirth, int year) {
  final birth = DateTime.tryParse('$rawBirth');
  final cutoff = DateTime(year, 3, 31);
  if (birth == null || birth.isAfter(cutoff)) return null;
  return year - birth.year - (birth.month > 3 ? 1 : 0);
}

const draftAttentionLabels = {
  'S': '競合必至',
  'A': '競合の可能性あり',
  'B': 'ドラ1候補',
  'C': '上位指名の可能性あり',
  'D': 'ドラフト指名の可能性あり',
  'E': '育成獲得の可能性あり',
};
int draftAttentionRank(Map<String, dynamic> p) {
  final rank = ['S', 'A', 'B', 'C', 'D', 'E'].indexOf('${p['attention_grade']}');
  return rank < 0 ? 6 : rank;
}

class StrengthAchievements extends StatelessWidget {
  const StrengthAchievements({super.key, required this.team, required this.year, this.comparisonTeams});
  final Map<String, dynamic> team;
  final int year;
  final List<Map<String, dynamic>>? comparisonTeams;
  @override
  Widget build(BuildContext context) {
    final roster = [
      for (final t in comparisonTeams ?? [team])
        for (final player in listMapFromJson(t['roster'])) (team: t, player: player),
    ]
        .indexed
        .map((entry) => (
              team: entry.$2.team,
              player: entry.$2.player,
              order: entry.$1,
              badges: groupAchievementHonors(consolidateCareerMilestones(playerHonors(entry.$2.player).where((a) => usageInt(a['year']) <= year).toList())),
            ))
        .toList()
      ..sort((a, b) {
        final countOrder = b.badges.length.compareTo(a.badges.length);
        return countOrder != 0 ? countOrder : a.order.compareTo(b.order);
      });
    return ListView.builder(
      key: ValueKey('achievement-list-${comparisonTeams == null ? team['id_team'] : 'comparison'}-$year'),
      itemCount: roster.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(padding: EdgeInsets.all(8), child: Text('選手は功績の多い順。評価の高い功績から左に並べ、空きを詰めて表示します。\nホバーで内容、クリックで詳細を表示します。'));
        }
        if (index == roster.length + 1) {
          return const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                  '取得・照合できた記録のみ表示。通算記録はNPBとMLBを別集計。優勝時のレギュラー認定は根拠を確認できた場合のみ付与します。代表選出は大会名簿、招集は強化試合等の名簿を根拠とします。レギュラー級の基準は各アイコンの詳細に表示します。ドラフト指名は入団確定を意味しません。未取得の受賞・記録があります。面積はアプリ独自の評価値に比例します（リーグMVP=100、個人タイトル=56.25、月間MVP=9、規定到達=4、三冠王=225、トリプルスリー=400）。公式な価値の比較ではありません。',
                  style: TextStyle(fontSize: 11, color: Colors.black54)));
        }
        final entry = roster[index - 1];
        final color = parseColorNameOrNull('${entry.team['color_back']}') ?? Colors.blueGrey;
        return Container(
          key: ValueKey('achievement-player-${entry.team['id_team']}-${usagePlayerKey(entry.player)}'),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black26))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 120,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (comparisonTeams != null)
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        color: color,
                        child: Text('${entry.team['name_team']}', style: TextStyle(fontSize: 11, color: parseColorNameOrNull('${entry.team['color_font']}') ?? (color.computeLuminance() > .45 ? Colors.black : Colors.white)))),
                  Text('${entry.player['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ])),
            Expanded(
                child: AchievementLayout(sizes: [
              for (final a in entry.badges) achievementBadgeSize(a) + 8
            ], children: [
              for (final a in entry.badges)
                IconButton(
                  tooltip: '${a['year']}年 ${a['label']}'
                      '${(a['detail'] ?? '').toString().isEmpty ? '' : '\n${a['detail']}'}',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  iconSize: achievementBadgeSize(a),
                  icon: AchievementBadge(achievement: a),
                  onPressed: () => showStrengthSource(context, '${entry.player['name']}：${a['label']}',
                      '${a['year']}年\n${a['detail'] ?? ''}\n表示評価値：${achievementValue(a)}（リーグMVP=100、面積比例・アプリ独自）', [if (a['source'] != null) '${a['source']}']),
                ),
            ])),
          ]),
        );
      },
    );
  }
}
