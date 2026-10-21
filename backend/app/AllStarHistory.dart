import 'AllStarPositions.dart';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';

String _text(Element? node) =>
    (node?.text ?? '').replaceAll(RegExp(r'[\s　]+'), ' ').trim();
String _compact(String text) => text.replaceAll(RegExp(r'[\s　]'), '');

/// Keep the selection positions used in the official roster; do not guess a
/// specific infield position for a player listed under the general 内野手 group.
List<Map<String, dynamic>> parseNpbAllStarRoster(String body, int year) {
  final doc = html.parse(body);
  final rows = <Map<String, dynamic>>[];
  final source = 'https://npb.jp/allstar/$year/roster.html';
  final hasLegend = doc
      .querySelectorAll('.contents p')
      .any((p) => p.text.contains('他') && p.text.contains('監督選抜'));
  final noteLines = doc
      .querySelectorAll('.att_box')
      .expand((e) => html
          .parseFragment(e.innerHtml.replaceAll(RegExp(r'<br\s*/?>'), '\n'))
          .text!
          .split('\n'))
      .map(_compact)
      .where((s) => s.isNotEmpty)
      .toList();
  for (final table in doc.querySelectorAll('table.player')) {
    Element? parent = table.parent;
    String league = '';
    while (parent != null && league.isEmpty) {
      final heading = _text(parent.querySelector('h5'));
      if (heading.contains('セントラル')) league = 'セ・リーグ';
      if (heading.contains('パシフィック')) league = 'パ・リーグ';
      parent = parent.parent;
    }
    if (league.isEmpty) continue;
    var position = '';
    for (final tr in table.querySelectorAll('tr')) {
      final heading = tr.querySelector('.position');
      if (heading != null) {
        position =
            _text(heading).replaceAll('指名打者', 'DH').replaceAll('中継ぎ投手', '中継投手');
      }
      final name = _text(tr.querySelector('td.name'));
      if (name.isEmpty ||
          position.isEmpty ||
          ['監督', 'コーチ'].contains(position)) {
        continue;
      }
      final marks = tr.querySelectorAll('td.mark,td.star').map(_text).join();
      final selections = <String>[
        if (marks.contains('◎')) 'ファン投票',
        if (marks.contains('☆')) '選手間投票',
        if (marks.contains('◇')) 'プラスワン投票',
        if (marks.contains('◆')) '補充選出',
      ];
      final compactName = _compact(name);
      var withdrawn = tr.querySelector('s,del,strike') != null;
      for (final line in noteLines) {
        final split = line.indexOf('を補充');
        if (split >= 0 &&
            line.substring(0, split).contains(compactName) &&
            !selections.contains('補充選出')) {
          selections.add('補充選出');
        }
        final withdrawalPart =
            line.contains('【') ? line.substring(line.indexOf('【')) : line;
        if (withdrawalPart.contains(compactName) &&
            RegExp(r'辞退|欠場').hasMatch(withdrawalPart)) {
          withdrawn = true;
        }
      }
      if (selections.isEmpty) selections.add(hasLegend ? '監督選抜' : '選出区分未確認');
      rows.add({
        'year': year,
        'league': league,
        'position': position,
        'name': name,
        'team': _text(tr.querySelector('td.team')),
        'number': _text(tr.querySelector('td.number')),
        'selections': selections,
        'withdrawn': withdrawn,
        'source': source,
        if (tr.querySelector('td.name a')?.attributes['href'] != null)
          'player_url': tr.querySelector('td.name a')!.attributes['href'],
      });
    }
  }
  return rows;
}

Map<String, dynamic> readAllStarHistory(int throughYear) {
  final root = Directory('data').existsSync() ? 'data' : 'backend/data';
  final file = File('$root/allstar_history.json');
  final catalog =
      file.existsSync() ? jsonDecode(file.readAsStringSync()) as Map : const {};
  final rows = [
    for (final row in catalog['players'] as List? ?? [])
      if ((row['year'] as int) <= throughYear)
        Map<String, dynamic>.from(row as Map)
  ];
  // The current season's scheduled award refresh also updates roster metadata.
  final current = File('$root/season_awards/$throughYear.json');
  if (current.existsSync()) {
    final snapshot = jsonDecode(current.readAsStringSync()) as Map;
    final roster = (snapshot['pages'] as Map? ??
            {})['allstar/$throughYear/roster.html'] as List? ??
        [];
    final enriched = roster
        .where((r) => r['league'] != null && r['selections'] is List)
        .toList();
    if (enriched.isNotEmpty) {
      rows.removeWhere((r) => r['year'] == throughYear);
      rows.addAll(enriched.map((r) => Map<String, dynamic>.from(r as Map)));
    }
  }
  final positions = File('$root/allstar_positions.json');
  if (positions.existsSync()) {
    applyAllStarPositions(
        rows, jsonDecode(positions.readAsStringSync()) as Map);
  }
  rows.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
  return {
    'players': rows,
    'through_year': throughYear,
    'first_year': catalog['first_year'],
    'cancelled_years': [
      for (final year in catalog['cancelled_years'] as List? ?? [])
        if (year <= throughYear) year
    ],
    'source': 'https://npb.jp/allstar/backnumber.html'
  };
}

/// Older rosters use a separate historical archive; preserve its attribution
/// and explicit selection marks instead of inferring selections from starters.
List<Map<String, dynamic>> parseHistoricalAllStarRoster(String body, int year) {
  final doc = html.parse(body);
  final result = <Map<String, dynamic>>[];
  final legend = doc.querySelector('.abstract')?.text ?? '';
  for (final tr in doc.querySelectorAll('table.chgtbl tr')) {
    final raw = _text(tr.querySelector('th.label'));
    if (raw.isEmpty || ['監督', 'コーチ'].contains(raw)) continue;
    final position = raw.contains('投手')
        ? '投手'
        : ['左翼手', '中堅手', '右翼手'].contains(raw)
            ? '外野手'
            : raw == '指名打者'
                ? 'DH'
                : raw;
    for (final td in tr.querySelectorAll('td.league')) {
      final side = td.classes.contains('l01')
          ? 'セ・リーグ'
          : td.classes.contains('l02')
              ? 'パ・リーグ'
              : '';
      if (side.isEmpty) continue;
      for (final player in td.querySelectorAll('.player')) {
        final name = _text(player.querySelector('.p_name'));
        if (name.isEmpty) continue;
        final mark = _text(player.querySelector('.mark'));
        final selections = <String>[
          if (mark.contains('◎')) 'ファン投票',
          if (mark.contains('☆')) '選手間投票',
          if (mark.contains('◇') && legend.contains('補充')) '補充選出',
        ];
        if (selections.isEmpty) {
          selections.add(legend.contains('監督推薦') ? '監督選抜' : '選出区分未確認');
        }
        result.add({
          'year': year,
          'league': side,
          'position': position,
          'name': name,
          'team': _text(player.querySelector('.t_name'))
              .replaceAll(RegExp(r'[()]'), ''),
          'selections': selections,
          'withdrawn': player.classes.contains('decline') ||
              player.querySelector('s,del,strike') != null,
          'source':
              'https://data-man.com/proyakyu/history/?format=players&type=allstar&y=$year',
          'source_label': 'プロ野球史 NPB MLB WBC（歴代名簿）'
        });
      }
    }
  }
  return result;
}
