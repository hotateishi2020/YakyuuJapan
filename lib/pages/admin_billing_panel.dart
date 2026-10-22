import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../logic/auth_session.dart';
import '../tools/Env.dart';

class AdminBillingPanel extends StatefulWidget {
  const AdminBillingPanel({super.key});
  @override
  State<AdminBillingPanel> createState() => _AdminBillingPanelState();
}

class _AdminBillingPanelState extends State<AdminBillingPanel> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String get month => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = [];
  Map<String, String> get headers => {
    'content-type': 'application/json',
    if (AuthSession.instance.token case final String token) 'Authorization': 'Bearer $token',
  };
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(Env.api('/admin/billing').replace(queryParameters: {'month': month}), headers: headers).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception(response.statusCode == 403 ? '管理者だけが利用できます' : '費用を取得できませんでした');
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      if (mounted) setState(() => _entries = (data['entries'] as List).map((r) => Map<String, dynamic>.from(r)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String amount(Map<String, dynamic> row) {
    final minor = int.parse('${row['amount_minor']}');
    return row['currency'] == 'USD' ? '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}' : '$minor';
  }

  Future<void> _edit(String provider, String kind, Map<String, dynamic>? row) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _BillingEditor(
      provider: provider, month: month, kind: kind, row: row, headers: headers,
    ));
    if (saved == true && mounted) await _load();
  }

  Widget _provider(String provider, String name, String url) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
        TextButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('公式管理画面')),
      ]),
      for (final kind in ['accrued', 'invoiced']) Builder(builder: (_) {
        final row = _entries.where((r) => r['provider'] == provider && r['kind'] == kind).firstOrNull;
        final checked = DateTime.tryParse('${row?['checked_at']}')?.toLocal();
        return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kind == 'accrued' ? '未確定利用額（対象月の確認時点）' : '対象月に発行された請求書の確定額（合計）'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(row == null ? '未登録' : '${row['currency']} ${amount(row)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              OutlinedButton(key: ValueKey('billing-edit-$provider-$kind'), onPressed: () => _edit(provider, kind, row), child: Text(row == null ? '金額を登録' : '更新')),
            ]),
            if (row != null) ...[
              Text('利用対象期間：${row['period']}'),
              Text('手動確認：${checked == null ? '不明' : checked.toString().split('.').first}', style: const TextStyle(fontSize: 12)),
            ],
          ],
        ));
      }),
    ]),
  ));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    Row(children: [
      IconButton(tooltip: '前月', onPressed: _loading ? null : () { _month = DateTime(_month.year, _month.month - 1); _load(); }, icon: const Icon(Icons.chevron_left)),
      Expanded(child: Text('$month の費用', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      IconButton(tooltip: '翌月', onPressed: _loading ? null : () { _month = DateTime(_month.year, _month.month + 1); _load(); }, icon: const Icon(Icons.chevron_right)),
      IconButton(tooltip: '再読み込み', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
    ]),
    const Padding(padding: EdgeInsets.all(8), child: Text('各社の請求画面で確認した金額を手動登録します。自動取得ではありません。未確定利用額と確定額は別の指標のため合算しません。請求書の利用対象期間は発行月と異なる場合があります。')),
    if (_loading) const Center(child: CircularProgressIndicator())
    else if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red)))
    else ...[
      _provider('neon', 'Neon', 'https://console.neon.tech/'),
      _provider('render', 'Render', 'https://dashboard.render.com/'),
    ],
  ]);
}

class _BillingEditor extends StatefulWidget {
  const _BillingEditor({required this.provider, required this.month, required this.kind, required this.row, required this.headers});
  final String provider, month, kind;
  final Map<String, dynamic>? row;
  final Map<String, String> headers;
  @override
  State<_BillingEditor> createState() => _BillingEditorState();
}
class _BillingEditorState extends State<_BillingEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount, _period;
  late String _currency;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _currency = widget.row?['currency'] ?? 'USD';
    final minor = int.tryParse('${widget.row?['amount_minor']}');
    _amount = TextEditingController(text: minor == null ? '' : _currency == 'USD' ? '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}' : '$minor');
    _period = TextEditingController(text: widget.row?['period'] ?? '');
  }
  @override
  void dispose() { _amount.dispose(); _period.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final response = await http.post(Env.api('/admin/billing'), headers: widget.headers, body: jsonEncode({
        'provider': widget.provider, 'month': widget.month, 'kind': widget.kind,
        'currency': _currency, 'amount': _amount.text.trim(), 'period': _period.text.trim(),
      })).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 403 ? '管理者だけが利用できます' : '保存できませんでした。入力内容を確認して再試行してください。');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_saving, child: AlertDialog(
    title: Text('${widget.provider == 'neon' ? 'Neon' : 'Render'} ${widget.month}\n${widget.kind == 'accrued' ? '未確定利用額' : '発行済み請求書の確定額（合計）'}'),
    content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(initialValue: _currency, decoration: const InputDecoration(labelText: '通貨'), items: [for (final c in ['USD', 'JPY']) DropdownMenuItem(value: c, child: Text(c))], onChanged: _saving ? null : (v) => setState(() => _currency = v!)),
      TextFormField(controller: _amount, enabled: !_saving, decoration: const InputDecoration(labelText: '金額'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => RegExp(_currency == 'JPY' ? r'^\d{1,9}$' : r'^\d{1,9}(\.\d{1,2})?$').hasMatch((v ?? '').trim()) ? null : '0以上の金額を入力してください（USDは小数2桁まで）'),
      TextFormField(controller: _period, enabled: !_saving, maxLength: 200, decoration: const InputDecoration(labelText: '利用対象期間', hintText: '例：2026年10月1日〜22日／請求書記載の期間'), validator: (v) => (v ?? '').trim().isEmpty ? '利用対象期間を入力してください' : null),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
    ]))),
    actions: [TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('キャンセル')), FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '保存中…' : '確認した金額を保存'))],
  ));
}
