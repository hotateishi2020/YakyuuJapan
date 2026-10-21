import 'dart:convert';
import 'dart:io';
import 'app/PlayerArt.dart';
import 'app/PlayerDetailSnapshot.dart';
import 'tools/Postgres.dart';

/// Export identities without credentials; register only explicitly reviewed files.
Future<void> main(List<String> args) async {
  final result = await Postgres.withConnection((c) async {
    if (args.length == 2 && args.first == 'verify') {
      final files = jsonDecode(await File(args[1]).readAsString()) as List;
      var verified = 0;
      final failures = <String>[];
      for (final path in files) {
        final record = Map<String, dynamic>.from(
            jsonDecode(await File('$path').readAsString()));
        if (record['reviewed'] != true) continue;
        final profile = Map<String, dynamic>.from(record['profile']);
        final detail = await PlayerDetailSnapshot.read(c,
            year: DateTime.now().year, leagues: [1, 2],
            identity: {'source_player_id': record['source_player_id'],
              'id_team': profile['id_team']});
        final image = detail['character_image'];
        if (detail['found'] != true || image is! Map || image['url'] == null ||
            !File('${PlayerArt.root}/${image['url'].toString().split('/').last}').existsSync()) {
          failures.add('${record['source_player_id']}');
        } else {
          verified++;
        }
      }
      return {'verified': verified, 'failures': failures};
    }
    if (args.length == 2 && args.first == 'register-reviewed') {
      final files = jsonDecode(await File(args[1]).readAsString()) as List;
      await PlayerArt.ensure(c);
      var count = 0;
      for (final path in files) {
        final record = Map<String, dynamic>.from(
            jsonDecode(await File('$path').readAsString()));
        if (record['reviewed'] != true) continue;
        if (record['status'] == 'registered') continue;
        if (record['edit_prompt'] != null) {
          record['prompt'] = '${record['prompt']}\nFinal edit: ${record['edit_prompt']}';
        }
        await PlayerArt.registerOfficial(
            c, record, await File('${record['image_path']}').readAsBytes());
        record['status'] = 'registered';
        await File('$path').writeAsString(
            const JsonEncoder.withIndent('  ').convert(record));
        count++;
      }
      return {'registered': count};
    }
    final teams = (await c.execute(
            'SELECT id,name_full,name_short,id_league FROM m_team WHERE id_league IN (1,2) ORDER BY id'))
        .map((r) => r.toColumnMap()).toList();
    final players = (await c.execute(
            'SELECT id,name_full,id_team,uniform_number,date_birth::text,year_retire,flg_delete FROM m_player WHERE id_team IN (SELECT id FROM m_team WHERE id_league IN (1,2))'))
        .map((r) => r.toColumnMap()).toList();
    final out = File('data/player-art-npb-identities.json');
    await out.writeAsString(jsonEncode({'teams': teams, 'players': players}));
    return {'teams': teams.length, 'players': players.length, 'path': out.path};
  });
  print(jsonEncode(result));
  exit(result['failures'] is List && (result['failures'] as List).isNotEmpty ? 1 : 0);
}
