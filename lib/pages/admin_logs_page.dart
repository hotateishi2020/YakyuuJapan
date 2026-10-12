import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../logic/auth_session.dart';
import '../tools/Env.dart';

/// 操作ログとエラーログを同じ時系列の表で見る。
class AdminLogsPage extends StatefulWidget {
  const AdminLogsPage({super.key});

  @override
  State<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _LogColumn {
  const _LogColumn(this.key, this.label, this.width);
  final String key;
  final String label;
  final double width;
}

const _columns = <_LogColumn>[
  _LogColumn('timestamp', '発生日時', 156),
  _LogColumn('log_type', '種別', 56),
  _LogColumn('level', 'レベル', 64),
  _LogColumn('user_id', 'ユーザー', 108),
  _LogColumn('screen_name', '画面', 108),
  _LogColumn('action', '操作・処理', 180),
  _LogColumn('status', '結果', 52),
  _LogColumn('details', '詳細', 140),
  _LogColumn('error_type', 'エラー種別', 120),
  _LogColumn('error_code', 'コード', 64),
  _LogColumn('error_message', 'メッセージ', 200),
  _LogColumn('source', '発生場所', 96),
  _LogColumn('function_name', '関数', 120),
  _LogColumn('file_name', 'ファイル', 120),
  _LogColumn('line_number', '行', 44),
  _LogColumn('api_path', 'API', 140),
  _LogColumn('http_status', 'HTTP', 52),
  _LogColumn('duration_ms', '時間', 64),
  _LogColumn('request_id', 'リクエストID', 140),
  _LogColumn('session_id', 'セッションID', 120),
  _LogColumn('app_version', 'バージョン', 72),
  _LogColumn('environment', '環境', 56),
];

class _AdminLogsPageState extends State<AdminLogsPage> {
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = const [];

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
      if (!mounted) return;
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
        _logs = _rowsOf(map);
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

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> map) {
    final raw = map['logs'];
    if (raw is List) {
      return [
        for (final row in raw)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    }
    final merged = <Map<String, dynamic>>[
      for (final row in (map['access'] as List? ?? const []))
        if (row is Map)
          {
            ...Map<String, dynamic>.from(row),
            'timestamp': row['crtat'] ?? '',
            'log_type': '操作',
            'level': 'INFO',
            'user_id': row['id_user'] ?? '',
            'action': '${row['memo'] ?? ''}'.trim().isEmpty ? '${row['method'] ?? ''} ${row['url'] ?? ''}'.trim() : row['memo'],
            'status': '成功',
            'api_path': row['url'] ?? '',
          },
      for (final row in (map['errors'] as List? ?? const []))
        if (row is Map)
          {
            ...Map<String, dynamic>.from(row),
            'timestamp': row['crtat'] ?? '',
            'log_type': 'エラー',
            'level': 'ERROR',
            'user_id': row['id_user'] ?? '',
            'action': row['message'] ?? '',
            'status': '失敗',
            'error_message': row['message'] ?? '',
            'stack_trace': row['stacktrace'] ?? '',
            'api_path': row['url'] ?? '',
          },
    ]..sort((a, b) => '${b['timestamp']}'.compareTo('${a['timestamp']}'));
    return merged;
  }

  String _cell(Map<String, dynamic> row, String key) {
    if (key == 'user_id') {
      final name = '${row['user_name'] ?? ''}'.trim();
      final id = '${row['user_id'] ?? ''}'.trim();
      if (name.isEmpty && (id.isEmpty || id == '0')) return 'ゲスト';
      if (name.isEmpty) return id;
      return '$name ($id)';
    }
    if (key == 'timestamp') {
      final text = '${row['timestamp'] ?? ''}'.replaceFirst('T', ' ');
      final dot = text.indexOf('.');
      return dot < 0 ? text : text.substring(0, dot);
    }
    if (key == 'duration_ms') {
      final text = '${row['duration_ms'] ?? ''}'.trim();
      if (text.isEmpty || text == 'null') return '';
      return '${text}ms';
    }
    final value = '${row[key] ?? ''}'.trim();
    if (value == 'null') return '';
    return value;
  }

  void _openDetail(Map<String, dynamic> row) {
    final stack = '${row['stack_trace'] ?? ''}'.trim();
    final contextText = '${row['context'] ?? ''}'.trim();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${_cell(row, 'log_type')} ${_cell(row, 'timestamp')}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(
                [
                  if (stack.isNotEmpty) 'スタックトレース\n$stack',
                  if (contextText.isNotEmpty) 'エラー詳細\n$contextText',
                  if (stack.isEmpty && contextText.isEmpty) _cell(row, 'action'),
                ].join('\n\n'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tableWidth = _columns.fold<double>(0, (sum, column) => sum + column.width);
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
                : _logs.isEmpty
                    ? const Center(child: Text('ログはありません'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return Scrollbar(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                height: constraints.maxHeight,
                                child: Column(
                                  children: [
                                    _headerRow(),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: _logs.length,
                                        itemBuilder: (context, index) => _dataRow(_logs[index]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow() {
    return ColoredBox(
      color: const Color(0xFF1F1F1F),
      child: Row(
        children: [
          for (final column in _columns)
            SizedBox(
              width: column.width,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(column.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(Map<String, dynamic> row) {
    final error = '${row['log_type'] ?? ''}' == 'エラー';
    return Material(
      color: error ? const Color(0xFFFFF1F0) : Colors.white,
      child: InkWell(
        onTap: () => _openDetail(row),
        child: DecoratedBox(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0)))),
          child: Row(
            children: [
              for (final column in _columns)
                SizedBox(
                  width: column.width,
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _cell(row, column.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
