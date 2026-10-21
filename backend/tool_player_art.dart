import 'dart:convert';
import 'dart:io';
import 'app/PlayerArt.dart';
import 'app/PlayerArtSchedule.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  try {
    if (args.isEmpty) {
      throw ArgumentError('Use sync | run | register <research.json> <image.png>');
    }
    if (args.first == 'run') {
      print(jsonEncode(await PlayerArtSchedule.run()));
    } else if (args.first == 'register-reviewed') {
      final manifest = jsonDecode(await File('data/player-art-initial-manifest.json').readAsString()) as List;
      var count = 0;
      await Postgres.withConnection((c) async {
        await PlayerArt.ensure(c);
        for (final path in manifest) {
          final r = Map<String, dynamic>.from(jsonDecode(await File('$path').readAsString()));
          if (r['reviewed'] != true) continue;
          if (r['edit_prompt'] != null) {
            r['prompt'] = '${r['prompt']}\nFinal edit: ${r['edit_prompt']}';
          }
          await PlayerArt.registerOfficial(c, r, await File('${r['image_path']}').readAsBytes());
          count++;
        }
      });
      print(jsonEncode({'registered': count}));
    } else if (args.first == 'register-official' && args.length == 3) {
      final r = Map<String, dynamic>.from(jsonDecode(await File(args[1]).readAsString()));
      await Postgres.withConnection((c) async {
        await PlayerArt.ensure(c);
        await PlayerArt.registerOfficial(c, r, await File(args[2]).readAsBytes());
      });
      print('registered official ${r['source_player_id']}');
    } else if (args.first == 'baseline') {
      print(await Postgres.withConnection((c) => PlayerArt.sync(c, baselineOnly: true)));
    } else if (args.first == 'sync') {
      print(await Postgres.withConnection((c) => PlayerArt.sync(c)));
    } else if (args.first == 'register' && args.length == 3) {
      final record = Map<String, dynamic>.from(jsonDecode(await File(args[1]).readAsString()));
      await Postgres.withConnection((c) async {
        await PlayerArt.ensure(c);
        final players = await PlayerArt.roster(c);
        for (final id in (record['player_ids'] as List)) {
          final p = players.singleWhere((p) => p['id'] == id);
          if ('${p['uniform_number']}' != '${record['number']}' || p['id_team'] != record['id_team']) {
            throw StateError('Roster mismatch for $id');
          }
          await PlayerArt.register(c, p, Map<String, dynamic>.from(record['research']), record['prompt'] as String, await File(args[2]).readAsBytes());
        }
      });
      print('registered ${record['player_ids']}');
    } else {
      throw ArgumentError('Invalid arguments');
    }
    exit(0);
  } catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}
