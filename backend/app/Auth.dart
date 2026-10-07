import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../tools/Postgres.dart';

/// メール＋パスワードのログイン / 新規登録 / セッショントークン / プロフィール。
class Auth {
  static const sessionDays = 30;
  static const _colors = [
    'red', 'blue', 'green', 'orange', 'purple', 'teal', 'crimson', 'navy', 'gold',
  ];

  static bool _schemaReady = false;
  static Future<void>? _schemaFlight;

  static Future<void> ensureSchema(Connection conn) async {
    if (_schemaReady) return;
    final existing = _schemaFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final done = Completer<void>();
    _schemaFlight = done.future;
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS t_user_session (
          token VARCHAR(80) PRIMARY KEY,
          id_user INTEGER NOT NULL,
          expire_at TIMESTAMPTZ NOT NULL,
          crtat TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute("ALTER TABLE m_user ADD COLUMN IF NOT EXISTS nickname VARCHAR(100) DEFAULT ''");
      await conn.execute("ALTER TABLE m_user ADD COLUMN IF NOT EXISTS name_handle VARCHAR(100) DEFAULT ''");
      await conn.execute('ALTER TABLE m_user ADD COLUMN IF NOT EXISTS id_team_fav INTEGER');
      await conn.execute('ALTER TABLE m_user ADD COLUMN IF NOT EXISTS id_player_fav INTEGER');
      await conn.execute('ALTER TABLE m_user ADD COLUMN IF NOT EXISTS flg_notify_news BOOLEAN DEFAULT TRUE');
      await conn.execute('ALTER TABLE m_user ADD COLUMN IF NOT EXISTS flg_notify_event BOOLEAN DEFAULT TRUE');
      _schemaReady = true;
      done.complete();
    } catch (e, st) {
      _schemaFlight = null;
      done.completeError(e, st);
      rethrow;
    }
  }

  static Future<Response> _withAuthDb(Future<Response> Function(Connection conn) fn) async {
    final work = Postgres.withConnection(fn, urgent: true);
    try {
      return await work.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      unawaited(work.catchError((_) => _json(503, {
            'ok': false,
            'error': 'ログインが混み合っています。少し待って再度お試しください',
          })));
      return _json(503, {
        'ok': false,
        'error': 'ログインが混み合っています。少し待って再度お試しください',
      });
    }
  }

  /// 先頭の @ を除いたログインID / ハンドル
  static String _normalizeHandle(String raw) {
    var s = raw.trim();
    while (s.startsWith('@')) {
      s = s.substring(1).trim();
    }
    return s;
  }

  static String hashPassword(String password, String salt) {
    final digest = sha256.convert(utf8.encode('$salt|$password'));
    return digest.toString();
  }

  static String _newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _newToken() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _looksHashed(String stored) =>
      stored.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(stored);

  static String _encodePassword(String password) {
    final salt = _newSalt();
    return 'sha256:$salt:${hashPassword(password, salt)}';
  }

  static Future<bool> _passwordMatches(Connection conn, int userId, String stored, String input) async {
    if (stored.startsWith('sha256:')) {
      final parts = stored.split(':');
      if (parts.length != 3) return false;
      return hashPassword(input, parts[1]) == parts[2];
    }
    if (stored == input) {
      final hashed = _encodePassword(input);
      await conn.execute(
        'UPDATE m_user SET password = \$1::text, updat = NOW() WHERE id = \$2::int',
        parameters: [hashed, userId],
      );
      return true;
    }
    if (_looksHashed(stored) && hashPassword(input, '') == stored) return true;
    return false;
  }

  static Map<String, dynamic> _publicUser(Map<String, dynamic> row) => {
        'id': row['id'],
        'name_last': row['name_last'] ?? '',
        'name_first': row['name_first'] ?? '',
        'nickname': row['nickname'] ?? '',
        'name_handle': row['name_handle'] ?? '',
        'mailaddress': row['mailaddress'] ?? '',
        'code_color': row['code_color'] ?? '',
        'id_team_fav': row['id_team_fav'],
        'id_player_fav': row['id_player_fav'],
        'name_team_fav': row['name_team_fav'] ?? '',
        'name_player_fav': row['name_player_fav'] ?? '',
        'flg_notify_news': row['flg_notify_news'] ?? true,
        'flg_notify_event': row['flg_notify_event'] ?? true,
        'flg_read_news': row['flg_read_news'] ?? true,
        'flg_read_event': row['flg_read_event'] ?? true,
      };

  static const _userSelect = '''
    SELECT u.id, u.name_last, u.name_first, u.nickname, u.name_handle, u.mailaddress, u.code_color,
           u.id_team_fav, u.id_player_fav,
           COALESCE(u.flg_notify_news, TRUE) AS flg_notify_news,
           COALESCE(u.flg_notify_event, TRUE) AS flg_notify_event,
           COALESCE(u.flg_read_news, TRUE) AS flg_read_news,
           COALESCE(u.flg_read_event, TRUE) AS flg_read_event,
           COALESCE(t.name_short, t.name_shortest, '') AS name_team_fav,
           CASE
             WHEN p.id IS NULL THEN ''
             ELSE COALESCE(p.name_full, COALESCE(p.name_last, '') || COALESCE(p.name_first, ''))
           END AS name_player_fav
    FROM m_user u
    LEFT JOIN m_team t ON t.id = u.id_team_fav
    LEFT JOIN m_player p ON p.id = u.id_player_fav
  ''';

  static Future<String> _createSession(Connection conn, int userId) async {
    final token = _newToken();
    final expire = DateTime.now().toUtc().add(const Duration(days: sessionDays));
    await conn.execute(
      '''
        INSERT INTO t_user_session (token, id_user, expire_at)
        VALUES (\$1::text, \$2::int, \$3::timestamptz)
      ''',
      parameters: [token, userId, expire.toIso8601String()],
    );
    return token;
  }

  static Future<Map<String, dynamic>?> _userById(Connection conn, int id) async {
    final rows = await conn.execute(
      '$_userSelect WHERE u.id = \$1::int AND COALESCE(u.flg_delete, FALSE) = FALSE LIMIT 1',
      parameters: [id],
    );
    if (rows.isEmpty) return null;
    return rows.first.toColumnMap();
  }

  static Future<int?> _requireUserId(Connection conn, Request request) async {
    await ensureSchema(conn);
    final token = _bearer(request);
    if (token == null) return null;
    final rows = await conn.execute(
      '''
        SELECT s.id_user
        FROM t_user_session s
        JOIN m_user u ON u.id = s.id_user
        WHERE s.token = \$1::text
          AND s.expire_at > NOW()
          AND COALESCE(u.flg_delete, FALSE) = FALSE
        LIMIT 1
      ''',
      parameters: [token],
    );
    if (rows.isEmpty) return null;
    return rows.first.toColumnMap()['id_user'] as int;
  }

  static Future<Response> register(Request request) async {
    return _withAuthDb((conn) async {
      await ensureSchema(conn);
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final mail = '${body['mailaddress'] ?? ''}'.trim().toLowerCase();
      final password = '${body['password'] ?? ''}';
      final handle = _normalizeHandle('${body['name_handle'] ?? body['user_id'] ?? ''}');
      final nameLast = '${body['name_last'] ?? ''}'.trim();
      if (mail.isEmpty || !mail.contains('@')) {
        return _json(400, {'ok': false, 'error': 'メールアドレスを入力してください'});
      }
      if (handle.isEmpty) {
        return _json(400, {'ok': false, 'error': 'ユーザーIDを入力してください'});
      }
      if (!RegExp(r'^[A-Za-z0-9_.-]{3,40}$').hasMatch(handle)) {
        return _json(400, {'ok': false, 'error': 'ユーザーIDは半角英数字と _ . - の3〜40文字です'});
      }
      if (password.length < 4) {
        return _json(400, {'ok': false, 'error': 'パスワードは4文字以上にしてください'});
      }
      final mailExists = await conn.execute(
        '''
          SELECT id FROM m_user
          WHERE lower(COALESCE(mailaddress, '')) = \$1::text
            AND COALESCE(flg_delete, FALSE) = FALSE
          LIMIT 1
        ''',
        parameters: [mail],
      );
      if (mailExists.isNotEmpty) {
        return _json(409, {'ok': false, 'error': 'このメールアドレスは既に登録されています'});
      }
      final handleExists = await conn.execute(
        '''
          SELECT id FROM m_user
          WHERE lower(COALESCE(name_handle, '')) = lower(\$1::text)
            AND COALESCE(flg_delete, FALSE) = FALSE
          LIMIT 1
        ''',
        parameters: [handle],
      );
      if (handleExists.isNotEmpty) {
        return _json(409, {'ok': false, 'error': 'このユーザーIDは既に使われています'});
      }
      final hashed = _encodePassword(password);
      final color = _colors[Random().nextInt(_colors.length)];
      final display = nameLast.isNotEmpty ? nameLast : handle;
      final inserted = await conn.execute(
        '''
          INSERT INTO m_user (name_last, name_first, name_handle, nickname, mailaddress, password, code_color, flg_delete, crtat, updat)
          VALUES (\$1::text, ''::text, \$2::text, \$1::text, \$3::text, \$4::text, \$5::text, FALSE, NOW(), NOW())
          RETURNING id
        ''',
        parameters: [display, handle, mail, hashed, color],
      );
      final id = inserted.first.toColumnMap()['id'] as int;
      final user = await _userById(conn, id);
      final token = await _createSession(conn, id);
      return _json(200, {
        'ok': true,
        'token': token,
        'expire_days': sessionDays,
        'user': _publicUser(user!),
      });
    });
  }

  static Future<Response> login(Request request) async {
    return _withAuthDb((conn) async {
      await ensureSchema(conn);
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final rawLogin = '${body['login'] ?? body['mailaddress'] ?? body['name_handle'] ?? ''}'.trim();
      final password = '${body['password'] ?? ''}';
      final key = _normalizeHandle(rawLogin);
      if (key.isEmpty || password.isEmpty) {
        return _json(400, {'ok': false, 'error': 'メールアドレスまたはユーザーIDとパスワードを入力してください'});
      }
      final rows = await conn.execute(
        '''
          SELECT id, password
          FROM m_user
          WHERE COALESCE(flg_delete, FALSE) = FALSE
            AND (
              lower(COALESCE(mailaddress, '')) = lower(\$1::text)
              OR lower(COALESCE(name_handle, '')) = lower(\$1::text)
            )
          ORDER BY id
          LIMIT 1
        ''',
        parameters: [key],
      );
      if (rows.isEmpty) {
        return _json(401, {'ok': false, 'error': 'メールアドレス／ユーザーIDまたはパスワードが違います'});
      }
      final row = rows.first.toColumnMap();
      final userId = row['id'] as int;
      final ok = await _passwordMatches(conn, userId, '${row['password'] ?? ''}', password);
      if (!ok) {
        return _json(401, {'ok': false, 'error': 'メールアドレス／ユーザーIDまたはパスワードが違います'});
      }
      final user = await _userById(conn, userId);
      final token = await _createSession(conn, userId);
      return _json(200, {
        'ok': true,
        'token': token,
        'expire_days': sessionDays,
        'user': _publicUser(user!),
      });
    });
  }

  static Future<Response> me(Request request) async {
    return _withAuthDb((conn) async {
      final userId = await _requireUserId(conn, request);
      if (userId == null) return _json(401, {'ok': false, 'error': '未ログイン'});
      final user = await _userById(conn, userId);
      if (user == null) return _json(401, {'ok': false, 'error': 'セッションが無効です'});
      return _json(200, {'ok': true, 'user': _publicUser(user)});
    });
  }

  static Future<Response> logout(Request request) async {
    return _withAuthDb((conn) async {
      await ensureSchema(conn);
      final token = _bearer(request);
      if (token != null) {
        await conn.execute('DELETE FROM t_user_session WHERE token = \$1::text', parameters: [token]);
      }
      return _json(200, {'ok': true});
    });
  }

  static Future<Response> changePassword(Request request) async {
    return _withAuthDb((conn) async {
      final userId = await _requireUserId(conn, request);
      if (userId == null) return _json(401, {'ok': false, 'error': '未ログイン'});
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final current = '${body['current_password'] ?? ''}';
      final next = '${body['new_password'] ?? ''}';
      if (current.isEmpty || next.isEmpty) {
        return _json(400, {'ok': false, 'error': '現在のパスワードと新しいパスワードを入力してください'});
      }
      if (next.length < 4) {
        return _json(400, {'ok': false, 'error': '新しいパスワードは4文字以上にしてください'});
      }
      final rows = await conn.execute(
        'SELECT password FROM m_user WHERE id = \$1::int LIMIT 1',
        parameters: [userId],
      );
      if (rows.isEmpty) return _json(404, {'ok': false, 'error': 'ユーザーが見つかりません'});
      final stored = '${rows.first.toColumnMap()['password'] ?? ''}';
      final ok = await _passwordMatches(conn, userId, stored, current);
      if (!ok) {
        return _json(401, {'ok': false, 'error': '現在のパスワードが違います'});
      }
      await conn.execute(
        'UPDATE m_user SET password = \$1::text, updat = NOW() WHERE id = \$2::int',
        parameters: [_encodePassword(next), userId],
      );
      return _json(200, {'ok': true});
    });
  }

  static Future<Response> updateProfile(Request request) async {
    return _withAuthDb((conn) async {
      final userId = await _requireUserId(conn, request);
      if (userId == null) return _json(401, {'ok': false, 'error': '未ログイン'});
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      // 画面上の「ニックネーム」は name_last に保存
      final nameLast = '${body['name_last'] ?? body['nickname'] ?? ''}'.trim();
      final mail = '${body['mailaddress'] ?? ''}'.trim().toLowerCase();
      final teamFav = int.tryParse('${body['id_team_fav'] ?? ''}');
      final playerFav = int.tryParse('${body['id_player_fav'] ?? ''}');
      if (nameLast.isEmpty) {
        return _json(400, {'ok': false, 'error': 'ニックネームを入力してください'});
      }
      if (mail.isEmpty || !mail.contains('@')) {
        return _json(400, {'ok': false, 'error': 'メールアドレスを入力してください'});
      }
      final dup = await conn.execute(
        '''
          SELECT id FROM m_user
          WHERE lower(COALESCE(mailaddress, '')) = \$1::text
            AND id <> \$2::int
            AND COALESCE(flg_delete, FALSE) = FALSE
          LIMIT 1
        ''',
        parameters: [mail, userId],
      );
      if (dup.isNotEmpty) {
        return _json(409, {'ok': false, 'error': 'このメールアドレスは既に使われています'});
      }
      if (teamFav != null) {
        final t = await conn.execute('SELECT id FROM m_team WHERE id = \$1::int LIMIT 1', parameters: [teamFav]);
        if (t.isEmpty) return _json(400, {'ok': false, 'error': '押しのチームが不正です'});
      }
      if (playerFav != null) {
        final p = await conn.execute('SELECT id FROM m_player WHERE id = \$1::int LIMIT 1', parameters: [playerFav]);
        if (p.isEmpty) return _json(400, {'ok': false, 'error': '押しの選手が不正です'});
      }
      await conn.execute(
        '''
          UPDATE m_user SET
            name_last = \$1::text,
            mailaddress = \$2::text,
            id_team_fav = \$3::int,
            id_player_fav = \$4::int,
            updat = NOW()
          WHERE id = \$5::int
        ''',
        parameters: [nameLast, mail, teamFav, playerFav, userId],
      );
      final user = await _userById(conn, userId);
      return _json(200, {'ok': true, 'user': _publicUser(user!)});
    });
  }

  static Future<Response> markRead(Request request) async {
    return _withAuthDb((conn) async {
      final userId = await _requireUserId(conn, request);
      if (userId == null) return _json(401, {'ok': false, 'error': '未ログイン'});
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final target = '${body['target'] ?? ''}'.trim().toLowerCase();
      if (target != 'news' && target != 'event') {
        return _json(400, {'ok': false, 'error': 'target は news または event です'});
      }
      if (target == 'news') {
        await conn.execute(
          'UPDATE m_user SET flg_read_news = TRUE, updat = NOW() WHERE id = \$1::int',
          parameters: [userId],
        );
      } else {
        await conn.execute(
          'UPDATE m_user SET flg_read_event = TRUE, updat = NOW() WHERE id = \$1::int',
          parameters: [userId],
        );
      }
      final user = await _userById(conn, userId);
      return _json(200, {'ok': true, 'user': _publicUser(user!)});
    });
  }

  static Future<Response> updateNotifications(Request request) async {
    return _withAuthDb((conn) async {
      final userId = await _requireUserId(conn, request);
      if (userId == null) return _json(401, {'ok': false, 'error': '未ログイン'});
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final news = body['flg_notify_news'] == true || '${body['flg_notify_news']}' == 'true';
      final event = body['flg_notify_event'] == true || '${body['flg_notify_event']}' == 'true';
      await conn.execute(
        '''
          UPDATE m_user SET
            flg_notify_news = \$1::bool,
            flg_notify_event = \$2::bool,
            updat = NOW()
          WHERE id = \$3::int
        ''',
        parameters: [news, event, userId],
      );
      final user = await _userById(conn, userId);
      return _json(200, {'ok': true, 'user': _publicUser(user!)});
    });
  }

  static Future<Response> listTeams(Request request) async {
    return _withAuthDb((conn) async {
      final rows = await conn.execute('''
        SELECT t.id, t.name_short, t.name_shortest, t.id_league,
               COALESCE(l.name_short, l.name_shortest, '') AS name_league
        FROM m_team t
        LEFT JOIN m_league l ON l.id = t.id_league
        WHERE COALESCE(t.flg_delete, FALSE) = FALSE
          AND t.id_league IN (1, 2, 3, 4)
        ORDER BY t.id_league, t.id
      ''');
      final teams = [
        for (final r in rows)
          {
            'id': r.toColumnMap()['id'],
            'name': r.toColumnMap()['name_short'] ?? r.toColumnMap()['name_shortest'] ?? '',
            'name_shortest': r.toColumnMap()['name_shortest'] ?? '',
            'id_league': r.toColumnMap()['id_league'],
            'name_league': r.toColumnMap()['name_league'] ?? '',
          }
      ];
      return _json(200, {'ok': true, 'teams': teams});
    });
  }

  static Future<Response> listPlayers(Request request) async {
    return _withAuthDb((conn) async {
      final teamId = int.tryParse(request.url.queryParameters['id_team'] ?? '');
      final q = (request.url.queryParameters['q'] ?? '').trim();
      if (teamId == null || teamId <= 0) {
        return _json(400, {'ok': false, 'error': 'チームを指定してください'});
      }
      final params = <Object?>[teamId];
      var sql = '''
        SELECT id, name_last, name_first,
               COALESCE(name_full, COALESCE(name_last, '') || COALESCE(name_first, '')) AS name_disp
        FROM m_player
        WHERE id_team = \$1::int
          AND COALESCE(flg_delete, FALSE) = FALSE
      ''';
      if (q.isNotEmpty) {
        params.add('%$q%');
        sql += '''
          AND (
            COALESCE(name_full, COALESCE(name_last, '') || COALESCE(name_first, '')) ILIKE \$2::text
            OR COALESCE(name_last, '') ILIKE \$2::text
            OR COALESCE(name_first, '') ILIKE \$2::text
          )
        ''';
      }
      sql += ' ORDER BY name_last, name_first LIMIT 200';
      final rows = await conn.execute(sql, parameters: params);
      final players = [
        for (final r in rows)
          {
            'id': r.toColumnMap()['id'],
            'name': r.toColumnMap()['name_disp'] ?? '',
            'name_last': r.toColumnMap()['name_last'] ?? '',
            'name_first': r.toColumnMap()['name_first'] ?? '',
          }
      ];
      return _json(200, {'ok': true, 'players': players});
    });
  }

  static String? _bearer(Request request) {
    final h = request.headers['authorization'] ?? request.headers['Authorization'] ?? '';
    if (h.toLowerCase().startsWith('bearer ')) {
      final t = h.substring(7).trim();
      if (t.isNotEmpty) return t;
    }
    final q = request.url.queryParameters['token']?.trim();
    if (q != null && q.isNotEmpty) return q;
    return null;
  }

  static Response _json(int status, Map<String, dynamic> body) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
