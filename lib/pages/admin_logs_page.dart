import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../logic/auth_session.dart';
import '../tools/Env.dart';

/// 操作ログとエラーログ。ユーザー名またはユーザーIDで絞り込む。
class AdminLogsPage extends StatefulWidget {
  const AdminLogsPage({super.key});

  @override
  State<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends State<AdminLogsPage> {
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _access = const [];
  List<Map<String, dynamic>> _errors = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = AuthSession.instance.token;
      final res = await http.get(
        Env.api('/admin/logs').replace(queryParameters: {'q': _query.text.trim()}),
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 403) {
        setState(() {
          _loading = false;
          _error = '管理者だけが開けます';
        });
        return;
      }
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'ログを読み込めませんでした';
        });
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _access = [
          for (final row in (map['access'] as List? ?? const []))
            if (row is Map) Map<String, dynamic>.from(row),
        ];
        _errors = [
          for (final row in (map['errors'] as List? ?? const []))
            if (row is Map) Map<String, dynamic>.from(row),
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'ログを読み込めませんでした';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('管理者'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: 'ユーザー名またはユーザーID',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loading ? null : _load, child: const Text('絞り込み')),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    children: [
                      const Text('操作ログ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (_access.isEmpty) const Text('ありません', style: TextStyle(fontSize: 12)),
                      for (final row in _access) _logTile(row, error: false),
                      const SizedBox(height: 16),
                      const Text('エラーログ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (_errors.isEmpty) const Text('ありません', style: TextStyle(fontSize: 12)),
                      for (final row in _errors) _logTile(row, error: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _logTile(Map<String, dynamic> row, {required bool error}) {
    final name = '${row['name_user'] ?? ''}'.trim();
    final id = '${row['id_user'] ?? ''}';
    final who = name.isEmpty ? 'ID $id' : '$name（$id）';
    final when = '${row['crtat'] ?? ''}';
    final memo = '${row['memo'] ?? ''}'.trim();
    final headline = error ? '${row['message'] ?? ''}' : (memo.isNotEmpty ? memo : '${row['method'] ?? ''} ${row['url'] ?? ''}'.trim());
    final detail = error ? '${row['url'] ?? ''}' : (memo.isNotEmpty ? '${row['url'] ?? ''}'.trim() : '${row['category'] ?? ''} ${row['code'] ?? ''}'.trim());
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text(detail.isEmpty ? '$when  $who' : '$when  $who\n$detail', style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
