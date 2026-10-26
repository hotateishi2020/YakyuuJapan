import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/PlayerIdentity.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final ohtaniNpb = await PlayerIdentity.find(conn, name: '大谷翔平', teamId: 9, source: 'npb', externalId: '01305137');
    final ohtaniMlb = await PlayerIdentity.find(conn, name: 'Shohei Ohtani', teamId: 40, source: 'mlb', externalId: '660271');
    check(ohtaniNpb != null && ohtaniNpb == ohtaniMlb, 'NPB/MLB source IDs did not resolve to the same player');
    final machado = <int?>{};
    for (final name in ['マチャド', 'マニー・マチャド', 'M.マチャド', 'Manny Machado', 'Manuel Arturo Machado']) {
      machado.add(await PlayerIdentity.find(conn, name: name, teamId: 41));
    }
    check(machado.length == 1 && !machado.contains(null), 'Machado aliases do not resolve to one player');
    final kike = <int?>{};
    for (final name in ['エンリケ・ヘルナンデス', 'キケ・ヘルナンデス', 'Kiké Hernández', 'Kike Hernandez']) {
      final resolved = await PlayerIdentity.find(conn, name: name, teamId: 40);
      kike.add(resolved);
    }
    check(kike.length == 1 && !kike.contains(null), 'Hernandez aliases do not resolve to one player');
    await conn.execute('BEGIN');
    try {
      var conflictRejected = false;
      try {
        await PlayerIdentity.find(conn, name: '大谷 翔平', teamId: 41, url: 'https://baseball.yahoo.co.jp/mlb/player/2100607/');
      } catch (error) {
        conflictRejected = '$error'.contains('Source ID/name conflict');
      }
      check(conflictRejected, 'A conflicting Japanese name was attached to another player URL');
      final id = await PlayerIdentity.ensure(conn, name: '髙橋 同一性テスト', teamId: 41, source: 'identity_test', externalId: 'rollback-only', birthDate: DateTime.utc(1900, 1, 1));
      check(id > 0, 'Test registration failed');
      final again = await PlayerIdentity.ensure(conn, name: '高橋同一性テスト', teamId: 41, source: 'identity_test', externalId: 'rollback-only', birthDate: DateTime.utc(1900, 1, 1));
      check(id == again, 'Orthographic variant created duplicate');
      await conn.execute("UPDATE m_player SET name_full='Identity Test English' WHERE id=\$1", parameters: [id]);
      final row = (await conn.execute('SELECT name_full,name_patterns FROM m_player WHERE id=\$1', parameters: [id])).single;
      check('${row[0]}' == '髙橋 同一性テスト', 'English refresh overwrote Japanese name');
      check((row[1] as List).contains('Identity Test English'), 'English alias not retained');
      final duplicate = await conn.execute("INSERT INTO m_player(name_full,id_team,date_birth) VALUES('高橋同一性テスト',41,'1900-01-01') RETURNING id");
      check(duplicate.isEmpty, 'Legacy INSERT guard did not prevent duplicate');
      final concurrent = (await conn.execute("SELECT register_player_identity('Different English Test',41,'1900-01-01','mlb','99999999999',NULL)")).single[0];
      check(concurrent == 0, 'Concurrent bilingual registration created a duplicate');

      final sqlKey = (await conn.execute("SELECT player_identity_key('Ｋｉｋｅ́ Ｈｅｒｎａ́ｎｄｅｚ')=player_identity_key('Kiké Hernández')")).single[0];
      check(sqlKey == true, 'SQL accent normalization mismatch');
    } finally {
      await conn.execute('ROLLBACK');
    }
    final oldReferences = (await conn.execute('SELECT count(*) FROM t_stats_player_latest t JOIN t_player_identity_merge m ON m.old_id=t.id_player')).single[0];
    check(oldReferences == 0, 'Rankings still reference merged IDs');
    final oldId = (await conn.execute('SELECT coalesce(merged_into_player_id,id) FROM m_player WHERE id=24966')).single[0];
    check(oldId == machado.single, 'Legacy player ID does not redirect to canonical identity');
    final summary = (await conn.execute("""SELECT
    (SELECT count(*) FROM t_player_identity_merge) merged,
    (SELECT count(*) FROM m_player WHERE NOT coalesce(flg_delete,false) AND coalesce(name_ja,'')<>'' AND identity_sources ? 'mlb') localized_mlb,
    (SELECT count(*) FROM t_player_identity_review WHERE status='pending') pending_reviews,
    (SELECT count(*) FROM m_player p WHERE NOT coalesce(p.flg_delete,false) AND p.merged_into_player_id IS NOT NULL) invalid_active_redirects
  """)).single.toColumnMap();
    final duplicates = await conn.execute("SELECT identity_sources->>'mlb',count(*) FROM m_player WHERE NOT coalesce(flg_delete,false) AND identity_sources ? 'mlb' GROUP BY 1 HAVING count(*)>1");
    check(duplicates.isEmpty, 'Multiple active players share MLB official ID');
    check(summary['invalid_active_redirects'] == 0, 'Merged player remains active');
    final report = {'aliases_verified': true, 'rollback_registration_tests': true, ...summary};
    File('data/player-identity-verification.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'checked_at': DateTime.now().toUtc().toIso8601String(), ...report})}\n');
    print(jsonEncode(report));
  });
  exit(0);
}
