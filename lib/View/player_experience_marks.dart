import 'package:flutter/material.dart';

List<String> playerExperienceLabels(Map<String, dynamic> player) {
  bool enabled(String key) =>
      ['true', 't', '1'].contains('${player[key]}'.toLowerCase());
  return [
    if (enabled('flg_npb_experience')) 'NPB',
    if (enabled('flg_wbc')) 'WBC',
  ];
}

class PlayerExperienceMarks extends StatelessWidget {
  const PlayerExperienceMarks({super.key, required this.player});
  final Map<String, dynamic> player;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (final label in playerExperienceLabels(player))
          Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Tooltip(
                message: label == 'NPB' ? 'NPB球団への在籍経験あり' : 'WBC出場経験あり',
                child: Container(
                  width: 26,
                  height: 13,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: label == 'NPB'
                        ? const Color(0xFFB5182B)
                        : const Color(0xFF174C87),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(label,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          height: 1,
                          fontWeight: FontWeight.bold)),
                ),
              )),
      ]);
}
