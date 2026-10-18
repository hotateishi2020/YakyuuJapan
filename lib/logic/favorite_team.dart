import 'auth_session.dart';

const _franchises = [
  ['巨人', 'ジャイアンツ'],
  ['阪神', 'タイガース'],
  ['dena', 'ベイスターズ', '大洋', '洋松'],
  ['広島', 'カープ'],
  ['ヤクルト', 'スワローズ', '国鉄', 'サンケイ', 'アトムズ'],
  ['中日', 'ドラゴンズ', '名古屋', '産業'],
  ['ソフトバンク', 'ホークス', 'ダイエー', '南海'],
  ['日本ハム', 'ファイターズ', '東映', '日拓', '東急'],
  ['ロッテ', 'マリーンズ', '東京オリオンズ', '大毎', '毎日'],
  ['楽天', 'イーグルス'],
  ['オリックス', '阪急', 'ブレーブス', 'ブルーウェーブ'],
  ['西武', 'ライオンズ', '西鉄', '太平洋', 'クラウン'],
];
String _normalize(String name) => name.toLowerCase().replaceAll(RegExp(r'[\s・･]'), '');

bool sameFavoriteTeamName(String favorite, String candidate) {
  final a = _normalize(favorite);
  final b = _normalize(candidate);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final mlbNamesakes = RegExp(r'サンフランシスコ|デトロイト|sanfrancisco|detroit');
  if (mlbNamesakes.hasMatch(a) || mlbNamesakes.hasMatch(b)) {
    return (a.length >= 3 && b.contains(a)) || (b.length >= 3 && a.contains(b) && !_franchises.any((names) => names.contains(b)));
  }
  for (final names in _franchises) {
    if (names.any(a.contains)) return names.any(b.contains);
  }
  // Full MLB names and their short labels, without confusing city names alone.
  return (a.length >= 3 && b.contains(a)) || (b.length >= 3 && a.contains(b));
}

/// Resolve only against available options; never force an absent team into a picker.
T? favoriteTeamOption<T>(Iterable<T> options, {
  int? Function(T)? id,
  required String Function(T) name,
}) {
  final session = AuthSession.instance;
  if (!session.isLoggedIn) return null;
  final user = session.user!;
  if (id != null && user.idTeamFav != null) {
    for (final option in options) {
      if (id(option) == user.idTeamFav) return option;
    }
  }
  for (final option in options) {
    if (sameFavoriteTeamName(user.nameTeamFav, name(option))) return option;
  }
  return null;
}

Map<String, dynamic>? favoriteTeamRow(Iterable<Map<String, dynamic>> rows) =>
    favoriteTeamOption(rows,
      id: (row) => int.tryParse('${row['id_team'] ?? row['id']}'),
      name: (row) => '${row['name_team'] ?? row['tab_label'] ?? row['name'] ?? ''}');
