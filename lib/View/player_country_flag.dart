import 'package:flutter/material.dart';

String playerCountryEmoji(Map<String, dynamic> player) {
  for (final key in ['emoji_display_country', 'emoji_country']) {
    final value = '${player[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return ['true', 't', '1'].contains('${player['flg_japan']}'.toLowerCase())
      ? '🇯🇵'
      : '';
}

class PlayerCountryFlag extends StatelessWidget {
  const PlayerCountryFlag({super.key, required this.player, this.size = 14});
  final Map<String, dynamic> player;
  final double size;
  @override
  Widget build(BuildContext context) {
    final flag = playerCountryEmoji(player);
    return SizedBox(
        width: size * 1.4,
        child: flag.isEmpty
            ? const SizedBox.shrink()
            : Tooltip(
                message: '$flag ${player['country_flag_basis'] ?? '出身国'}',
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(flag,
                        style: TextStyle(fontSize: size, height: 1)))));
  }
}
