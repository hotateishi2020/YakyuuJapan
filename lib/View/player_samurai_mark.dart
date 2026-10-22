import 'package:flutter/material.dart';
import '../logic/display_settings.dart';

const samuraiCategories = <String, (String, Color)>{
  'wbc': ('WBC', Colors.black),
  'olympics': ('五輪代表', Color(0xFFC62828)),
  'premier12': ('プレミア12', Color(0xFF264478)),
  'other': ('その他の侍ジャパン代表', Color(0xFF757575)),
};

bool showsSamuraiMark(Map<String, dynamic> player) =>
    DisplaySettings.instance.shows('flg_samurai') &&
    samuraiCategories.containsKey(player['samurai_category']);

class PlayerSamuraiMark extends StatelessWidget {
  const PlayerSamuraiMark({super.key, required this.player});
  final Map<String, dynamic> player;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
        valueListenable: DisplaySettings.instance,
        builder: (context, _, child) {
          if (!showsSamuraiMark(player)) return const SizedBox.shrink();
          final category = samuraiCategories[player['samurai_category']]!;
          final selections = player['samurai_selections'];
          final details = <String>[];
          if (selections is List) {
            for (final selection in selections.whereType<Map>()) {
              final label = samuraiCategories[selection['category']]?.$1;
              final years = selection['years'];
              if (label != null) {
                details.add(
                    '$label${years is List ? '（${years.join('・')}年）' : ''}');
              }
            }
          }
          return Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Tooltip(
              message:
                  '侍ジャパン選出歴：${details.isEmpty ? category.$1 : details.join('、')}',
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: category.$2, borderRadius: BorderRadius.circular(3)),
                child: const Text('侍',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          );
        },
      );
}
