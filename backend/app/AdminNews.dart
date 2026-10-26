import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'Auth.dart';

Map<String, String> validateAdminNews(Object? value) {
  if (value is! Map) throw const FormatException('入力形式が正しくありません');
  final result = <String, String>{};
  for (final field in ['title', 'text_main', 'url', 'code_tag_main', 'code_tag_sub']) {
    final text = value[field];
    if (text != null && text is! String) {
      throw const FormatException('文字列で入力してください');
    }
    result[field] = (text as String? ?? '').trim();
  }
  if (result['title']!.isEmpty || result['title']!.length > 100) {
    throw const FormatException('タイトルは1〜100文字で入力してください');
  }
  if (result['text_main']!.length > 10000) {
    throw const FormatException('本文は10,000文字以内で入力してください');
  }
  if (result['url']!.isNotEmpty) {
    final uri = Uri.tryParse(result['url']!);
    if (result['url']!.length > 2000 || uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('リンクURLはhttpまたはhttpsのURLを入力してください');
    }
  }
  if (result['code_tag_main']!.length > 20 || result['code_tag_sub']!.length > 20) {
    throw const FormatException('タグが正しくありません');
  }
  return result;
}

class AdminNews {
  static Response json(int status, Object body) => Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});
  static Future<List<Map<String, dynamic>>> tags(Connection conn) async => (await conn.execute("SELECT code,key,name1 AS label,code_color1,code_color2 FROM m_system_code WHERE code IN ('NORTIFICATION','NORTIFICATION_SUB') ORDER BY code,key")).map((r) => r.toColumnMap()).toList();
  static Future<Response> read(Connection conn, Request request) async {
    if (await Auth.adminUserId(conn, request) == null) {
      return json(403, {'error': '管理者だけが利用できます'});
    }
    final items = await conn.execute('SELECT id,title,text_main,url,code_tag_main,code_tag_sub,crtat::text AS created_at FROM t_nortification WHERE NOT COALESCE(flg_delete,false) AND id_user IS NULL ORDER BY id DESC LIMIT 50');
    return json(200, {'news': items.map((r) => r.toColumnMap()).toList(), 'tags': await tags(conn)});
  }

  static Future<Response> create(Connection conn, Request request) async {
    final admin = await Auth.adminUserId(conn, request);
    if (admin == null) return json(403, {'error': '管理者だけが利用できます'});
    Map<String, String> input;
    try {
      final body = await request.readAsString();
      if (body.length > 50000) return json(400, {'error': '入力内容が長すぎます'});
      input = validateAdminNews(jsonDecode(body));
    } on FormatException catch (e) {
      return json(400, {'error': e.message});
    }
    final choices = await tags(conn);
    for (final entry in {'code_tag_main': 'NORTIFICATION', 'code_tag_sub': 'NORTIFICATION_SUB'}.entries) {
      if (input[entry.key]!.isNotEmpty && !choices.any((r) => r['code'] == entry.value && '${r['key']}' == input[entry.key])) {
        return json(400, {'error': '選択したタグは利用できません'});
      }
    }
    final item = await conn.runTx((tx) async {
      final inserted = await tx.execute(r'''INSERT INTO t_nortification
        (title,text_main,url,code_tag_main,code_tag_sub,id_user,flg_read,flg_delete,crtby,updby,crtpgm,updpgm)
        VALUES ($1,$2,$3,$4,$5,NULL,FALSE,FALSE,$6,$6,'ADMIN_NEWS','ADMIN_NEWS')
        RETURNING id,title,text_main,url,code_tag_main,code_tag_sub,crtat::text AS created_at''', parameters: [input['title'], input['text_main'], input['url'], input['code_tag_main']!.isEmpty ? null : input['code_tag_main'], input['code_tag_sub']!.isEmpty ? null : input['code_tag_sub'], admin]);
      return inserted.single.toColumnMap();
    });
    return json(201, {'ok': true, 'news': item});
  }
}
