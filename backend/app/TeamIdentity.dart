import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';

/// Legacy m_team IDs remain stable franchise references for games and players.
/// Season identities store the name used then, independently of today's club.
class TeamIdentity {
  static Future<void> ensure(Connection conn) async {
    await conn.execute('''CREATE TABLE IF NOT EXISTS m_team_franchise (
      id integer PRIMARY KEY REFERENCES m_team(id),
      lineage_key text NOT NULL UNIQUE,
      created_at timestamptz NOT NULL DEFAULT now())''');
    await conn.execute('''CREATE TABLE IF NOT EXISTS m_team_season_identity (
      id_franchise integer NOT NULL REFERENCES m_team_franchise(id),
      int_year integer NOT NULL,
      name_full text NOT NULL,
      name_short text NOT NULL,
      name_shortest text,
      color_back text,
      color_font text,
      logo_url text,
      source text NOT NULL DEFAULT 't_stats_team.name_team',
      updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (id_franchise,int_year))''');
  }

  static Future<int> refreshVisuals(Connection conn, {int? year}) async {
    final file = [File('data/team_identity_visuals.json'), File('backend/data/team_identity_visuals.json')]
        .firstWhere((f) => f.existsSync());
    var updated = 0;
    for (final v in jsonDecode(await file.readAsString()) as List) {
      final rows = await conn.execute(r'''UPDATE m_team_season_identity
        SET name_short=$1,color_back=$2,color_font=$3,
            logo_url=COALESCE($4,logo_url),updated_at=now()
        WHERE name_full=$5 AND ($6::integer IS NULL OR int_year=$6)
        RETURNING id_franchise''', parameters: [v['short_name'],v['color_back'],v['color_font'],v['logo_url'],v['name'],year]);
      updated += rows.length;
    }
    return updated;
  }

  static Future<void> sync(Connection conn, {int? year}) async {
    await ensure(conn);
    await conn.execute('''INSERT INTO m_team_franchise(id,lineage_key)
      SELECT id,'legacy-team:' || id::text FROM m_team
      ON CONFLICT(id) DO NOTHING''');
    // Never derive an old name from today's m_team name. Missing evidence stays missing.
    await conn.execute('''INSERT INTO m_team_season_identity
      (id_franchise,int_year,name_full,name_short,name_shortest)
      SELECT DISTINCT ON(s.id_team,s.year) s.id_team,s.year,trim(s.name_team),
        trim(s.name_team),NULLIF(trim(s.name_shortest),'')
      FROM t_stats_team s
      WHERE (\$1::integer IS NULL OR s.year=\$1) AND s.year>0
        AND NOT COALESCE(s.flg_delete,false) AND NULLIF(trim(s.name_team),'') IS NOT NULL
      ORDER BY s.id_team,s.year,s.crtat DESC,s.id DESC
      ON CONFLICT(id_franchise,int_year) DO UPDATE SET
        name_full=excluded.name_full,
        name_short=CASE WHEN m_team_season_identity.name_full=excluded.name_full
          THEN m_team_season_identity.name_short ELSE excluded.name_short END,
        name_shortest=excluded.name_shortest,updated_at=now()''', parameters: [year]);
    await refreshVisuals(conn, year: year);
  }
}
