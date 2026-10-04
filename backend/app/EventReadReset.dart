import '../tools/Postgres.dart';

/// イベントの開始日・最終日に全ユーザーの flg_read_event を false にする。
/// 同一日の再実行は t_job_event_read_reset で抑止する。
class EventReadReset {
  static Future<void> tick() async {
    try {
      await Postgres.withConnection((conn) async {
        await conn.execute('''
          CREATE TABLE IF NOT EXISTS t_job_event_read_reset (
            reset_on DATE PRIMARY KEY,
            crtat TIMESTAMPTZ DEFAULT NOW()
          )
        ''');

        final todayRows = await conn.execute(
          "SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Tokyo')::date AS today",
        );
        final today = todayRows.first.toColumnMap()['today'];

        final already = await conn.execute(
          'SELECT 1 FROM t_job_event_read_reset WHERE reset_on = \$1::date LIMIT 1',
          parameters: [today],
        );
        if (already.isNotEmpty) return;

        final hit = await conn.execute(
          '''
            SELECT 1
            FROM (
              SELECT date_from::date AS d_from, date_to::date AS d_to
              FROM t_event
              WHERE date_from IS NOT NULL OR date_to IS NOT NULL
              UNION ALL
              SELECT datetime_start::date AS d_from, NULL::date AS d_to
              FROM t_event_details
              WHERE datetime_start IS NOT NULL
            ) e
            WHERE e.d_from = \$1::date
               OR e.d_to = \$1::date
            LIMIT 1
          ''',
          parameters: [today],
        );
        if (hit.isEmpty) return;

        await conn.execute('''
          UPDATE m_user
          SET flg_read_event = FALSE, updat = NOW()
          WHERE COALESCE(flg_delete, FALSE) = FALSE
        ''');
        await conn.execute(
          'INSERT INTO t_job_event_read_reset (reset_on) VALUES (\$1::date) ON CONFLICT DO NOTHING',
          parameters: [today],
        );
        print('EventReadReset: flg_read_event=false for all users (date=$today)');
      });
    } catch (e, st) {
      print('EventReadReset ERROR: $e\n$st');
    }
  }
}
