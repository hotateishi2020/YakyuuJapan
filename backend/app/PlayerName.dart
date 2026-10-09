import '../tools/StringTool.dart';

/// Yahoo MLB などで使う選手名の分解・照合。
/// 例: `J.チョウリオ` → initial=J, surname=チョウリオ
class PlayerNameParts {
  final String compact;
  final String? initial;
  final String surname;
  final String core; // イニシャル無しの本体（姓、またはフル）

  const PlayerNameParts({
    required this.compact,
    required this.initial,
    required this.surname,
    required this.core,
  });

  bool get hasInitial => initial != null && initial!.isNotEmpty;
}

final _abbrRe = RegExp(r'^([A-Za-z]{1,3})[\.．](.+)$');

PlayerNameParts parsePlayerName(String raw) {
  final compact = StringTool.noSpace(raw);
  final m = _abbrRe.firstMatch(compact);
  if (m != null) {
    final initial = m.group(1)!.toUpperCase();
    final surname = m.group(2)!;
    return PlayerNameParts(
      compact: compact,
      initial: initial,
      surname: surname,
      core: surname,
    );
  }
  final parts = compact.split('・');
  final surname = parts.isNotEmpty ? parts.last : compact;
  return PlayerNameParts(
    compact: compact,
    initial: null,
    surname: surname,
    core: compact,
  );
}

/// name_full / name_last からイニシャルを取り出す（`J.チョウリオ` や `CJ.エイブラムズ`）。
String? extractNameFirstInitial(String raw) {
  final parsed = parsePlayerName(raw);
  return parsed.hasInitial ? parsed.initial : null;
}

/// ロスター行との照合。abbr↔フル（J.チョウリオ ↔ ジャクソン・チョウリオ）も許す。
bool playerNameMatches({
  required String query,
  required String nameFull,
  String nameLast = '',
  String? storedInitial,
}) {
  final q = parsePlayerName(query);
  final full = StringTool.noSpace(nameFull);
  final last = StringTool.noSpace(nameLast);
  if (q.compact.isEmpty || full.isEmpty) return false;
  if (full == q.compact || last == q.compact) return true;
  if (full.startsWith(q.compact) || last.startsWith(q.compact)) return true;

  final initial = (storedInitial ?? '').trim().toUpperCase();
  final fullParts = parsePlayerName(full);
  final lastParts = parsePlayerName(last.isNotEmpty ? last : full);

    if (q.hasInitial) {
    final qInit = q.initial!;
    final qSur = q.surname;
    // ロスターが同じ略称
    if (fullParts.hasInitial && fullParts.initial == qInit && fullParts.surname == qSur) return true;
    if (lastParts.hasInitial && lastParts.initial == qInit && lastParts.surname == qSur) return true;
    // 登録イニシャルが一致しても、フル名の読みが食い違うときは別人。
    if ((initial == qInit || fullParts.initial == qInit) &&
        !_givenContradictsInitial(full, qInit) &&
        !_givenContradictsInitial(last, qInit)) {
      if (_surnameMatches(full, qSur) || _surnameMatches(last, qSur)) return true;
    }
    // イニシャル未登録でも、姓一致を候補に（後段で一意なら採用）。
    // ヘーゲン・スミスと C.スミスのように名が食い違うときは別人。
    if ((_surnameMatches(full, qSur) || _surnameMatches(last, qSur)) && !_givenContradictsInitial(full, qInit) && !_givenContradictsInitial(last, qInit)) {
      return true;
    }
  } else {
    // ブレーデン・モンゴメリー ↔ コルソン・モンゴメリー は別人。
    if (_isFullPersonalName(q) && _isFullPersonalName(fullParts) && q.compact != fullParts.compact) {
      return false;
    }
    // モンゴメリー ↔ ブレーデン・モンゴメリー
    if (_surnameMatches(full, q.compact) || _surnameMatches(last, q.compact)) return true;
    final rosterInitial = fullParts.hasInitial ? fullParts.initial! : (lastParts.hasInitial ? lastParts.initial : null);
    if ((_surnameMatches(q.compact, fullParts.surname) || _surnameMatches(q.compact, lastParts.surname)) &&
        (rosterInitial == null || !_givenContradictsInitial(q.compact, rosterInitial))) {
      return true;
    }
    // クエリがフル、ロスターが略称
    if (fullParts.hasInitial && _surnameMatches(q.compact, fullParts.surname)) {
      if (!_givenContradictsInitial(q.compact, fullParts.initial!) && (initial.isEmpty || initial == fullParts.initial)) return true;
    }
    if (lastParts.hasInitial && _surnameMatches(q.compact, lastParts.surname)) {
      if (!_givenContradictsInitial(q.compact, lastParts.initial!) && (initial.isEmpty || initial == lastParts.initial)) return true;
    }
  }
  return false;
}

bool _givenContradictsInitial(String fullName, String initial) {
  final given = fullName.split('・').first;
  if (!fullName.contains('・') || given.isEmpty || given == fullName) return false;
  return !_givenMatchesInitial(given, initial);
}

bool _givenMatchesInitial(String given, String initial) {
  final letter = initial.trim().toUpperCase();
  if (letter.isEmpty) return false;
  if (RegExp(r'^[A-Za-zＡ-Ｚ]+$').hasMatch(given)) {
    return given.toUpperCase() == letter || given == initial;
  }
  final possible = _kanaInitials(given);
  if (possible.isEmpty) return true;
  return possible.contains(letter[0]);
}

String _kanaInitials(String given) {
  const digraphs = {
    'ウィ': 'W',
    'ウェ': 'W',
    'ウォ': 'W',
    'ヴァ': 'V',
    'ヴィ': 'V',
    'ヴェ': 'V',
    'ヴォ': 'V',
    'チェ': 'C',
    'シェ': 'S',
    'ジェ': 'J',
    'ティ': 'T',
    'ディ': 'D',
    'ファ': 'F',
    'フィ': 'F',
    'フェ': 'F',
    'フォ': 'F',
  };
  const kana = {
    'ア': 'A',
    'イ': 'IY',
    'ウ': 'U',
    'エ': 'E',
    'オ': 'O',
    'カ': 'KC',
    'キ': 'KC',
    'ク': 'KCQ',
    'ケ': 'KC',
    'コ': 'KC',
    'サ': 'S',
    'シ': 'S',
    'ス': 'S',
    'セ': 'SC',
    'ソ': 'S',
    'タ': 'T',
    'チ': 'CT',
    'ツ': 'TS',
    'テ': 'T',
    'ト': 'T',
    'ナ': 'N',
    'ニ': 'N',
    'ヌ': 'N',
    'ネ': 'N',
    'ノ': 'N',
    'ハ': 'H',
    'ヒ': 'H',
    'フ': 'FH',
    'ヘ': 'H',
    'ホ': 'H',
    'マ': 'M',
    'ミ': 'M',
    'ム': 'M',
    'メ': 'M',
    'モ': 'M',
    'ヤ': 'Y',
    'ユ': 'YU',
    'ヨ': 'Y',
    'ラ': 'RL',
    'リ': 'RL',
    'ル': 'RL',
    'レ': 'RL',
    'ロ': 'RL',
    'ワ': 'W',
    'ヲ': 'O',
    'ン': 'N',
    'ガ': 'G',
    'ギ': 'G',
    'グ': 'G',
    'ゲ': 'G',
    'ゴ': 'G',
    'ザ': 'ZJ',
    'ジ': 'JG',
    'ズ': 'Z',
    'ゼ': 'ZJ',
    'ゾ': 'Z',
    'ダ': 'D',
    'デ': 'D',
    'ド': 'D',
    'バ': 'BV',
    'ビ': 'BV',
    'ブ': 'BV',
    'ベ': 'BV',
    'ボ': 'BV',
    'パ': 'P',
    'ピ': 'P',
    'プ': 'P',
    'ペ': 'P',
    'ポ': 'P',
  };
  if (given.length >= 2) {
    final two = digraphs[given.substring(0, 2)];
    if (two != null) return two;
  }
  if (given.isEmpty) return '';
  return kana[given.substring(0, 1)] ?? '';
}

bool _isFullPersonalName(PlayerNameParts parts) {
  if (parts.hasInitial) return false;
  return parts.compact.contains('・') && parts.surname.isNotEmpty && parts.core != parts.surname;
}

bool _surnameMatches(String fullOrLast, String surname) {
  final a = StringTool.noSpace(fullOrLast);
  final b = StringTool.noSpace(surname);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.endsWith(b) || b.endsWith(a)) return true;
  if (a.contains('・')) {
    final tail = a.split('・').last;
    if (tail == b || tail.endsWith(b) || b.endsWith(tail)) return true;
  }
  return false;
}

/// フル名の読みと食い違う登録イニシャルを、読みの頭文字に直す。食い違わなければ null。
String? correctedNameInitial(String nameFull, String stored) {
  final compact = StringTool.noSpace(nameFull);
  if (!compact.contains('・')) return null;
  final given = compact.split('・').first;
  final possible = _kanaInitials(given);
  if (possible.isEmpty) return null;
  final current = stored.trim().toUpperCase();
  if (current.isNotEmpty && possible.contains(current[0])) return null;
  return possible[0];
}

/// 候補が複数あるとき、クエリと同一の氏名を優先し、なければイニシャルで絞る。
int? pickBestPlayerId({
  required String query,
  required List<({int id, String nameFull, String nameLast, String initial})> candidates,
}) {
  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first.id;
  final q = parsePlayerName(query);
  final exact = candidates.where((c) {
    final full = StringTool.noSpace(c.nameFull);
    final last = StringTool.noSpace(c.nameLast);
    return full == q.compact || last == q.compact;
  }).toList();
  if (exact.isNotEmpty) {
    exact.sort((a, b) => a.id.compareTo(b.id));
    return exact.first.id;
  }
  if (q.hasInitial) {
    final withInit = candidates.where((c) {
      final stored = c.initial.trim().toUpperCase();
      final parsed = parsePlayerName(c.nameFull);
      return stored == q.initial || parsed.initial == q.initial;
    }).toList();
    if (withInit.length == 1) return withInit.first.id;
    if (withInit.length > 1) {
      // 姓の一致度が高い方
      withInit.sort((a, b) {
        final as = _surnameMatches(a.nameFull, q.surname) ? 0 : 1;
        final bs = _surnameMatches(b.nameFull, q.surname) ? 0 : 1;
        if (as != bs) return as.compareTo(bs);
        return a.nameFull.length.compareTo(b.nameFull.length);
      });
      return withInit.first.id;
    }
  }
  // 最短名を優先（従来どおり）
  candidates = [...candidates]..sort((a, b) {
      final byLen = a.nameFull.length.compareTo(b.nameFull.length);
      if (byLen != 0) return byLen;
      return a.id.compareTo(b.id);
    });
  final shortest = candidates.first.nameFull.length;
  final ties = candidates.where((c) => c.nameFull.length == shortest).toList();
  if (ties.length == 1) return ties.first.id;
  return null;
}
