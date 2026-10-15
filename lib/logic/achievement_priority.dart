import 'dart:math' as math;

/// App display priorities, not an official ranking of baseball achievements.
/// Specific awards precede broad terms (e.g. monthly MVP before season MVP).
int achievementPriority(Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? ''}'.toLowerCase();
  final kind = achievement['kind'];
  bool has(String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(label);
  if (has('史上初|歴代|新記録|年間最多|通算最多|最多.*更新|all.time|historic')) return 100;
  if (has('三冠王|triple crown')) return 96;
  if (has('50-50')) return 94;
  if (has('40-40')) return 90;
  if (has('トリプルスリー')) return 86;
  if (kind == 'record') return 92;
  if (has('正力松太郎')) return has('特別') ? 83 : 89;
  if (has('完全試合')) return 92;
  if (has('ノーヒットノーラン')) return 82;
  if (kind == 'national_team') return 48;
  if (kind == 'callup') return 32;
  if (kind == 'draft') return 28;
  if (has('of the week|週間|週刊')) return 30;
  if (has('月間|of the month')) return 45;
  if (has('cs mvp|クライマックス.*mvp|championship series.*mvp|lcs.*mvp')) return 72;
  if (has('pool.*mvp')) return 65;
  if (has('world series.*mvp|日本シリーズmvp|world baseball classic.*mvp|wbc.*mvp'))
    return 85;
  if (has('mvp|最優秀選手|most valuable|cy young|サイ.?ヤング|沢村(?:栄治)?賞')) return 88;
  if (kind == 'milestone') {
    final n =
        int.tryParse(RegExp(r'通算\s*(\d+)').firstMatch(label)?.group(1) ?? '') ??
            0;
    if (has('本塁打|home run'))
      return n >= 500
          ? 90
          : n >= 300
              ? 80
              : n >= 200
                  ? 65
                  : 55;
    if (has('勝|wins')) return n >= 200 ? 90 : 70;
    if (has('安打|hits'))
      return n >= 3000
          ? 94
          : n >= 2000
              ? 86
              : 65;
    if (has('セーブ|saves'))
      return n >= 300
          ? 88
          : n >= 200
              ? 78
              : 60;
    if (has('奪三振|strikeout'))
      return n >= 3000
          ? 92
          : n >= 2000
              ? 82
              : 65;
    return 50;
  }
  if (kind == 'championship') {
    if (has('wbc|world baseball classic|日本一|world series')) return 65;
    return 55;
  }
  if (kind == 'qualification' || has('規定打席|規定投球')) return 20;
  if (has('新人王|最優秀新人|rookie of the year')) return 74;
  if (has(
      '首位打者|最多本塁打|最多打点|最多盗塁|最多勝|最多奪三振|最多セーブ|最優秀防御率|最優秀中継ぎ|最高勝率|勝率第一位|hank aaron|batting champion|home run leader'))
    return 76;
  if (has('ベストナイン|gold glove|ゴールデングラブ|silver slugger|all.mlb')) return 68;
  if (has('all.star|オールスター')) return 50;
  return kind == 'title' ? 60 : 35;
}

/// Higher priority first, then recent year, then label for deterministic ties.
int compareAchievementPriority(Map<String, dynamic> a, Map<String, dynamic> b) {
  final priority = achievementPriority(b).compareTo(achievementPriority(a));
  if (priority != 0) return priority;
  int year(Map<String, dynamic> v) => int.tryParse('${v['year']}') ?? 0;
  final recent = year(b).compareTo(year(a));
  return recent != 0 ? recent : '${a['label']}'.compareTo('${b['label']}');
}

/// Recognize season league MVPs without enlarging monthly/series MVPs.
bool isLeagueMvp(Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? ''}'
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '');
  return RegExp(
          r'^(?:(?:npb|mlb|al|nl|americanleague|nationalleague|セ[・･]?リーグ|パ[・･]?リーグ)[・･:]?)?(?:mvp|最優秀選手(?:賞)?|mostvaluableplayer(?:award)?)$')
      .hasMatch(label);
}

/// Use the award's own league/source, never the player's present-day team.
String leagueMvpCaption(Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? ''}'.toLowerCase();
  final source = Uri.tryParse('${achievement['source'] ?? ''}')?.path ?? '';
  if (RegExp(r'/award/\d+/cl\.html$').hasMatch(source) ||
      label.contains('セ・リーグ') ||
      label.contains('セリーグ')) return 'セMVP';
  if (RegExp(r'/award/\d+/pl\.html$').hasMatch(source) ||
      label.contains('パ・リーグ') ||
      label.contains('パリーグ')) return 'パMVP';
  if (RegExp(r'\bal\b|american league').hasMatch(label)) return 'アMVP';
  if (RegExp(r'\bnl\b|national league').hasMatch(label)) return 'ナMVP';
  return 'MVP';
}

/// Editorial display values, not official rankings. Area, rather than diameter,
/// is proportional to this value; league MVP is the reference value of 100.
double achievementValue(Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? ''}'.toLowerCase();
  final kind = achievement['kind'];
  bool has(String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(label);
  if (has('史上初|歴代|新記録|年間最多|通算最多|最多.*更新|all.time|historic')) return 600;
  if (has('50-50|トリプルスリー')) return 400;
  if (has('三冠王|triple crown|40-40')) return 225;
  if (isLeagueMvp(achievement) || has('cy young|サイ.?ヤング|沢村(?:栄治)?賞'))
    return 100;
  if (has('正力松太郎')) return has('特別') ? 64 : 100;
  if (has('完全試合')) return 144;
  if (has('ノーヒットノーラン')) return 64;
  if (kind == 'national_team') return 9;
  if (kind == 'callup') return 4;
  if (kind == 'draft') return has('育成') ? 2.25 : 4;
  if (has('月間|of the month')) return 9;
  if (has('週間|週刊|of the week')) return 4;
  if (kind == 'qualification' || has('規定打席|規定投球')) return 4;
  if (has('cs mvp|クライマックス.*mvp|lcs.*mvp|championship series.*mvp')) return 25;
  if (has('world series.*mvp|日本シリーズmvp|wbc.*mvp|world baseball classic.*mvp'))
    return 64;
  if (kind == 'championship') return has('wbc|world series|日本一|金メダル') ? 16 : 9;
  if (kind == 'milestone') {
    final n =
        int.tryParse(RegExp(r'通算\s*(\d+)').firstMatch(label)?[1] ?? '') ?? 0;
    if (has('本塁打|home run|勝|wins|安打|hits|セーブ|saves|奪三振|strikeout')) {
      final priority = achievementPriority(achievement);
      return priority >= 90
          ? 225
          : priority >= 80
              ? 100
              : priority >= 65
                  ? 49
                  : n > 0
                      ? 25
                      : 16;
    }
    return 25;
  }
  if (has('新人王|最優秀新人|rookie of the year')) return 36;
  if (has('ベストナイン|gold glove|ゴールデングラブ|silver slugger|all.mlb')) return 25;
  if (has('all.star|オールスター')) return 6.25;
  if (kind == 'title') return 56.25;
  if (kind == 'record') return 100;
  return 9;
}

double achievementBadgeSize(Map<String, dynamic> achievement) =>
    96 * math.sqrt(achievementValue(achievement) / 100);
