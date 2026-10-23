import 'package:flutter/material.dart';
import '../logic/draft_competition.dart';

String draftSchoolCategory(Map player) {
  final explicit = '${player['category'] ?? ''}';
  if (const {'中学生', '高校生', '大学生', '社会人', '独立リーグ'}.contains(explicit)) return explicit;
  final from = '${player['from'] ?? ''}';
  if (from.isEmpty || from == '—') return '';
  if (RegExp(r'独立|BCリーグ|四国|徳島|香川|愛媛|高知ファイティング|武蔵|埼玉武蔵|群馬|福島|信濃|新潟アルビ|富山|石川ミリオン|福井|滋賀|栃木|茨城|神奈川フューチャー|琉球|北九州|大分B|火の国|愛媛MP|高知FD').hasMatch(from) && !RegExp(r'大学|高校|高等|大$|高$|中$').hasMatch(from)) return '独立リーグ';
  if (RegExp(r'中学校|中学|中$').hasMatch(from)) return '中学生';
  if (RegExp(r'高校|高等|高$').hasMatch(from)) return '高校生';
  if (RegExp(r'大学|大$').hasMatch(from)) return '大学生';
  return '社会人';
}

Color draftLabelColor(String label) => switch (label) {
  '単独指名' => Colors.black,
  '中学生' => Colors.purple.shade700,
  '高校生' => Colors.red.shade700,
  '大学生' => Colors.blue.shade700,
  '社会人' => Colors.green.shade700,
  '独立リーグ' => Colors.orange.shade800,
  _ => label.contains('競合') ? Colors.deepOrange.shade700 : label.startsWith('ハズレ') ? Colors.blue.shade700 : Colors.green.shade700,
};

Color draftPositionColor(String position) {
  if (position.contains('投手')) return Colors.red.shade100;
  if (position.contains('捕手')) return Colors.blue.shade100;
  if (RegExp('内野|一塁|二塁|三塁|遊撃').hasMatch(position)) return Colors.yellow.shade100;
  if (RegExp('外野|左翼|中堅|右翼').hasMatch(position)) return Colors.green.shade100;
  return Colors.grey.shade100;
}

class DraftLabels extends StatelessWidget {
  const DraftLabels({super.key, required this.player});
  final Map player;
  @override
  Widget build(BuildContext context) {
    final category = draftSchoolCategory(player);
    return Wrap(spacing: 3, runSpacing: 3, children: [
      for (final label in [if (category.isNotEmpty) category, ...draftNominationLabels(player)])
        Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: draftLabelColor(label), borderRadius: BorderRadius.circular(3)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 1, softWrap: false,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)))),
    ]);
  }
}
