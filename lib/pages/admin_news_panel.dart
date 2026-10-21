import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../logic/auth_session.dart';
import '../tools/Env.dart';
import '../widgets/baseball_loading.dart';

class AdminNewsPanel extends StatefulWidget {
  const AdminNewsPanel({super.key});
  @override
  State<AdminNewsPanel> createState() => _AdminNewsPanelState();
}

class _AdminNewsPanelState extends State<AdminNewsPanel> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _url = TextEditingController();
  String _main = '', _sub = '';
  bool _loading = true, _saving = false;
  String? _error, _success;
  List<Map<String, dynamic>> _tags = [], _news = [];
  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (AuthSession.instance.token case final String token) 'Authorization': 'Bearer $token',
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _url.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList() : [];
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(Env.api('/admin/news'), headers: _headers).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 403 ? '管理者だけが利用できます' : 'Newsを読み込めませんでした');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      setState(() {
        _tags = _rows(data['tags']);
        _news = _rows(data['news']);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final response = await http
          .post(Env.api('/admin/news'),
              headers: _headers,
              body: jsonEncode({
                'title': _title.text.trim(),
                'text_main': _body.text.trim(),
                'url': _url.text.trim(),
                'code_tag_main': _main,
                'code_tag_sub': _sub,
              }))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Map data = {};
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      } catch (_) {}
      if (response.statusCode != 201) {
        setState(() => _error = '${data['error'] ?? (response.statusCode == 403 ? '管理者だけが利用できます' : '登録できませんでした。入力内容は保持しています。')}');
        return;
      }
      setState(() {
        if (data['news'] is Map) {
          _news.insert(0, Map<String, dynamic>.from(data['news']));
        }
        _title.clear();
        _body.clear();
        _url.clear();
        _success = 'Newsを登録しました';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '登録結果を確認できませんでした。登録済みNewsを再読み込みしてから再試行してください。入力内容は保持しています。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tag(String code, String label, String selected, ValueChanged<String> change) => DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [const DropdownMenuItem(value: '', child: Text('なし')), for (final tag in _tags.where((t) => t['code'] == code)) DropdownMenuItem(value: '${tag['key']}', child: Text('${tag['label']}'))],
        onChanged: _saving ? null : (value) => setState(() => change(value ?? '')),
      );
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: BaseballLoading());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('News登録', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('登録するとNews欄に公開されます。'),
                    const SizedBox(height: 16),
                    TextFormField(controller: _title, enabled: !_saving, maxLength: 100, decoration: const InputDecoration(labelText: 'タイトル（必須）', border: OutlineInputBorder()), validator: (v) => (v ?? '').trim().isEmpty ? 'タイトルを入力してください' : null),
                    const SizedBox(height: 12),
                    TextFormField(controller: _body, enabled: !_saving, minLines: 4, maxLines: 10, maxLength: 10000, decoration: const InputDecoration(labelText: '本文', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    _tag('NORTIFICATION', 'メインタグ', _main, (v) => _main = v),
                    const SizedBox(height: 12),
                    _tag('NORTIFICATION_SUB', 'サブタグ', _sub, (v) => _sub = v),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _url,
                        enabled: !_saving,
                        maxLength: 2000,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'リンクURL（任意）', border: OutlineInputBorder()),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          final uri = Uri.tryParse(text);
                          return uri != null && ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty ? null : 'httpまたはhttpsのURLを入力してください';
                        }),
                    if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                    if (_success != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_success!, style: const TextStyle(color: Colors.green))),
                    FilledButton(onPressed: _saving || _error == '管理者だけが利用できます' ? null : _save, child: Text(_saving ? '登録中…' : 'Newsを登録')),
                    const SizedBox(height: 24),
                    Row(children: [const Expanded(child: Text('登録済みNews（最新50件）', style: TextStyle(fontWeight: FontWeight.bold))), IconButton(tooltip: 'Newsを再読み込み', onPressed: _saving ? null : _load, icon: const Icon(Icons.refresh))]),
                    if (_news.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('登録済みのNewsはありません')),
                    for (final item in _news) Card(child: ListTile(title: Text('${item['title'] ?? ''}'), subtitle: Text([if ('${item['text_main'] ?? ''}'.isNotEmpty) '${item['text_main']}', if ('${item['url'] ?? ''}'.isNotEmpty) '${item['url']}', if (item['created_at'] != null) '${item['created_at']}'].join('\n')))),
                  ])))),
    ]);
  }
}
