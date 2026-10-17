import 'dart:io';
import 'tools/Postgres.dart';
import 'app/DisplaySnapshot.dart';
import 'app/PostseasonForm.dart';
import 'app/StrengthUsage.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  await Postgres.withConnection((conn) async {
    final snap = await DisplaySnapshot.games(conn, year);
    final chosen = <int, Map<String, dynamic>>{};
    final ordered = [...snap.games]
      ..sort((a, b) => '${b['date_game']}'.compareTo('${a['date_game']}'));
    for (final g in ordered) {
      final league = usageInt(g['id_league_home']);
      if ('${g['state']}'.contains('終了') &&
          postseasonCodes.contains('${g['code_game']}'.toUpperCase()) &&
          '${g['date_game']}'.compareTo(
                  DateTime.now().toIso8601String().substring(0, 10)) <=
              0) chosen.putIfAbsent(league, () => Map<String, dynamic>.from(g));
    }
    final games = chosen.values.toList();
    await attachPostseasonForm(conn, games, year);
    for (final g in games) {
      final all = usageMaps(g['postseason_form']);
      final names = snap.games
          .where((r) => r['id_game'] == g['id_game'])
          .map((r) => usageName('${r['name_full_summary'] ?? ''}'))
          .where((s) => s.isNotEmpty)
          .toSet();
      final matched = all
          .where((r) =>
              r['level'] != null && names.contains(usageName('${r['name']}')))
          .toList();
      final participants = (await conn.execute(
              'SELECT DISTINCT s.id_player,p.name_full, (s.double_inning_pitch>0 OR s.int_pitch>0) AS pitcher FROM t_game_summary s JOIN m_player p ON p.id=s.id_player WHERE s.id_game=\$1 AND NOT COALESCE(s.flg_delete,false) AND (s.double_inning_pitch>0 OR s.int_pitch>0 OR s.int_batting>0)',
              parameters: [g['id_game']]))
          .map((r) => r.toColumnMap())
          .toList();
      final missing = <Map<String, dynamic>>[];
      for (final p in participants) {
        final form = all
            .where((f) =>
                f['id_player'] == p['id_player'] &&
                f['pitcher'] == p['pitcher'])
            .firstOrNull;
        if (form?['level'] != null) continue;
        final careers = await conn.execute(
            'SELECT id_player,int_batting,double_average_batting,double_inning,double_average_earned_runs FROM m_player_career WHERE id_player=\$1 AND int_year=\$2 AND NOT COALESCE(flg_delete,false)',
            parameters: [p['id_player'], year]);
        missing.add({
          ...p,
          'form': form,
          'careers': careers.map((r) => r.toColumnMap()).toList()
        });
      }
      print({
        'game': g['id_game'],
        'participants': participants.length,
        'missing': missing,
        'date': g['date_game'],
        'time': g['time_game'],
        'series': g['code_game'],
        'registered_hands': usageMaps(g['player_hands'])
            .where(
                (r) => r['pitching_hand'] != null && r['batting_hand'] != null)
            .length,
        'forms': all.where((r) => r['level'] != null).length,
        'displayed_players_with_form':
            matched.map((r) => r['id_player']).toSet().length,
        'examples': matched
            .take(3)
            .map((r) => {
                  'name': r['name'],
                  'label': r['label'],
                  'season': r['season'],
                  'recent': r['postseason'],
                  'sample': r['sample']
                })
            .toList()
      });
    }
    if (games.isEmpty) throw StateError('検証対象のPS試合がありません');
  });
  exit(0);
}
