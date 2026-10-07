import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../tools/Env.dart';
import '../tools/browser_cookie.dart';

const authTokenCookie = 'koko_auth_token';
const authUserCookie = 'koko_auth_user';
const _sessionMaxAge = 30 * 24 * 60 * 60; // 30日

String authNetworkError(Object e, String action) {
  final text = e.toString().toLowerCase();
  if (text.contains('timeoutexception') || text.contains('timed out')) {
    return '$actionがタイムアウトしました。少し待って再度お試しください';
  }
  return '通信エラー: $e';
}

/// デバッグ起動時の自動ログイン（本番ビルドでは使わない）
const _debugLoginMail = 'hotateishi2018@gmail.com';
const _debugLoginPassword = 'tate0224';

class AuthUser {
  final int id;
  final String nameLast;
  final String nameFirst;
  final String nickname;
  final String nameHandle;
  final String mailaddress;
  final String codeColor;
  final int? idTeamFav;
  final int? idPlayerFav;
  final String nameTeamFav;
  final String namePlayerFav;
  final bool notifyNews;
  final bool notifyEvent;
  /// false のとき News に New を出す
  final bool readNews;
  /// false のときイベント日程に New を出す
  final bool readEvent;

  const AuthUser({
    required this.id,
    required this.nameLast,
    required this.nameFirst,
    required this.nickname,
    required this.nameHandle,
    required this.mailaddress,
    required this.codeColor,
    this.idTeamFav,
    this.idPlayerFav,
    this.nameTeamFav = '',
    this.namePlayerFav = '',
    this.notifyNews = true,
    this.notifyEvent = true,
    this.readNews = true,
    this.readEvent = true,
  });

  /// ヘッダー等の表示名は name_last（ニックネーム）のみ
  String get displayName {
    final last = nameLast.trim();
    if (last.isNotEmpty) return last;
    final handle = nameHandle.trim();
    if (handle.isNotEmpty) return handle;
    return mailaddress;
  }

  static bool _asBool(dynamic value, {bool fallback = true}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '$value'.trim().toLowerCase();
    if (text == 'true' || text == 't' || text == '1') return true;
    if (text == 'false' || text == 'f' || text == '0') return false;
    return fallback;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: int.tryParse('${json['id']}') ?? 0,
        nameLast: '${json['name_last'] ?? ''}',
        nameFirst: '${json['name_first'] ?? ''}',
        nickname: '${json['nickname'] ?? ''}',
        nameHandle: '${json['name_handle'] ?? ''}',
        mailaddress: '${json['mailaddress'] ?? ''}',
        codeColor: '${json['code_color'] ?? ''}',
        idTeamFav: int.tryParse('${json['id_team_fav'] ?? ''}'),
        idPlayerFav: int.tryParse('${json['id_player_fav'] ?? ''}'),
        nameTeamFav: '${json['name_team_fav'] ?? ''}',
        namePlayerFav: '${json['name_player_fav'] ?? ''}',
        notifyNews: _asBool(json['flg_notify_news']),
        notifyEvent: _asBool(json['flg_notify_event']),
        readNews: _asBool(json['flg_read_news']),
        readEvent: _asBool(json['flg_read_event']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_last': nameLast,
        'name_first': nameFirst,
        'nickname': nickname,
        'name_handle': nameHandle,
        'mailaddress': mailaddress,
        'code_color': codeColor,
        'id_team_fav': idTeamFav,
        'id_player_fav': idPlayerFav,
        'name_team_fav': nameTeamFav,
        'name_player_fav': namePlayerFav,
        'flg_notify_news': notifyNews,
        'flg_notify_event': notifyEvent,
        'flg_read_news': readNews,
        'flg_read_event': readEvent,
      };
}

class AuthSession {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  AuthUser? user;
  String? token;

  bool get isLoggedIn => user != null && (token?.isNotEmpty ?? false);

  bool get showNewsNew => isLoggedIn && !(user?.readNews ?? true);
  bool get showEventNew => isLoggedIn && !(user?.readEvent ?? true);
  bool get showInfoNew => showNewsNew || showEventNew;

  Map<String, String> get _authHeaders => {
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
        'content-type': 'application/json; charset=utf-8',
      };

  Future<void> restore() async {
    final saved = readBrowserCookie(authTokenCookie);
    if (saved == null || saved.isEmpty) {
      user = null;
      token = null;
      await _debugAutoLoginIfNeeded();
      return;
    }
    token = saved;
    user = _readCachedUser();
    try {
      final res = await http.get(
        Env.api('/auth/me'),
        headers: {'Authorization': 'Bearer $saved'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 401 || res.statusCode == 403) {
        clearLocal();
        await _debugAutoLoginIfNeeded();
        return;
      }
      if (res.statusCode != 200) {
        await _debugAutoLoginIfNeeded();
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (map['ok'] != true) {
        clearLocal();
        await _debugAutoLoginIfNeeded();
        return;
      }
      user = AuthUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      _persistSession();
    } catch (_) {
      await _debugAutoLoginIfNeeded();
    }
  }

  /// デバッグ時のみ、未ログインなら固定アカウントでログインする。
  Future<void> _debugAutoLoginIfNeeded() async {
    if (!kDebugMode || isLoggedIn) return;
    await login(login: _debugLoginMail, password: _debugLoginPassword);
  }

  Future<String?> login({required String login, required String password}) async {
    try {
      final res = await http
          .post(
            Env.api('/auth/login'),
            headers: {'content-type': 'application/json; charset=utf-8'},
            body: jsonEncode({'login': login, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || map['ok'] != true) {
        return '${map['error'] ?? 'ログインに失敗しました'}';
      }
      _applyAuthResponse(map);
      return null;
    } catch (e) {
      return authNetworkError(e, 'ログイン');
    }
  }

  Future<String?> register({
    required String mailaddress,
    required String nameHandle,
    required String password,
    String nameLast = '',
  }) async {
    try {
      final res = await http
          .post(
            Env.api('/auth/register'),
            headers: {'content-type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'mailaddress': mailaddress,
              'name_handle': nameHandle,
              'password': password,
              'name_last': nameLast,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || map['ok'] != true) {
        return '${map['error'] ?? '登録に失敗しました'}';
      }
      _applyAuthResponse(map);
      return null;
    } catch (e) {
      return authNetworkError(e, '登録');
    }
  }

  Future<void> logout() async {
    final t = token;
    clearLocal();
    if (t == null || t.isEmpty) return;
    try {
      await http
          .post(
            Env.api('/auth/logout'),
            headers: {'Authorization': 'Bearer $t'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<String?> changePassword({required String currentPassword, required String newPassword}) async {
    try {
      final res = await http
          .post(
            Env.api('/auth/change-password'),
            headers: _authHeaders,
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || map['ok'] != true) {
        return '${map['error'] ?? 'パスワード変更に失敗しました'}';
      }
      return null;
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  Future<String?> updateProfile({
    required String nameLast,
    required String mailaddress,
    int? idTeamFav,
    int? idPlayerFav,
  }) async {
    try {
      final res = await http
          .post(
            Env.api('/auth/profile'),
            headers: _authHeaders,
            body: jsonEncode({
              'name_last': nameLast,
              'mailaddress': mailaddress,
              'id_team_fav': idTeamFav,
              'id_player_fav': idPlayerFav,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || map['ok'] != true) {
        return '${map['error'] ?? '基本設定の保存に失敗しました'}';
      }
      if (map['user'] is Map) {
        user = AuthUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      }
      return null;
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  Future<String?> markRead(String target) async {
    try {
      final res = await http
          .post(
            Env.api('/auth/mark-read'),
            headers: _authHeaders,
            body: jsonEncode({'target': target}),
          )
          .timeout(const Duration(seconds: 15));
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || map['ok'] != true) {
        return '${map['error'] ?? '既読更新に失敗しました'}';
      }
      if (map['user'] is Map) {
        user = AuthUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      }
      return null;
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  Future<String?> updateNotifications({required bool notifyNews, required bool notifyEvent}) async {
    try {
      final res = await http
          .post(
            Env.api('/auth/notifications'),
            headers: _authHeaders,
            body: jsonEncode({
              'flg_notify_news': notifyNews,
              'flg_notify_event': notifyEvent,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || map['ok'] != true) {
        return '${map['error'] ?? '通知設定の保存に失敗しました'}';
      }
      if (map['user'] is Map) {
        user = AuthUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      }
      return null;
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  Future<List<Map<String, dynamic>>> fetchTeams() async {
    final res = await http.get(Env.api('/auth/teams')).timeout(const Duration(seconds: 20));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || map['ok'] != true) return const [];
    final list = map['teams'];
    if (list is! List) return const [];
    return [for (final e in list) Map<String, dynamic>.from(e as Map)];
  }

  Future<List<Map<String, dynamic>>> fetchPlayers({required int idTeam, String q = ''}) async {
    final uri = Env.api('/auth/players').replace(queryParameters: {
      'id_team': '$idTeam',
      if (q.trim().isNotEmpty) 'q': q.trim(),
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || map['ok'] != true) return const [];
    final list = map['players'];
    if (list is! List) return const [];
    return [for (final e in list) Map<String, dynamic>.from(e as Map)];
  }

  void _applyAuthResponse(Map<String, dynamic> map) {
    token = '${map['token'] ?? ''}';
    user = AuthUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
    _persistSession();
  }

  void _persistSession() {
    if (token != null && token!.isNotEmpty) {
      writeBrowserCookie(authTokenCookie, token!, maxAgeSeconds: _sessionMaxAge);
    }
    if (user != null) {
      writeBrowserCookie(authUserCookie, jsonEncode(user!.toJson()), maxAgeSeconds: _sessionMaxAge);
    }
  }

  AuthUser? _readCachedUser() {
    final raw = readBrowserCookie(authUserCookie);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) return AuthUser.fromJson(map);
      if (map is Map) return AuthUser.fromJson(Map<String, dynamic>.from(map));
    } catch (_) {}
    return null;
  }

  void clearLocal() {
    user = null;
    token = null;
    clearBrowserCookie(authTokenCookie);
    clearBrowserCookie(authUserCookie);
  }
}
