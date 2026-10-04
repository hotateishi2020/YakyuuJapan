import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/auth_session.dart';

Future<void> showAccountMenu(BuildContext context, {VoidCallback? onChanged}) async {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;

  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<String>(
    context: context,
    position: position,
    items: const [
      PopupMenuItem(value: 'password', child: Text('パスワード変更')),
      PopupMenuItem(value: 'notify', child: Text('通知設定')),
      PopupMenuItem(value: 'profile', child: Text('基本設定')),
    ],
  );
  if (!context.mounted || action == null) return;

  switch (action) {
    case 'password':
      await showChangePasswordDialog(context);
      break;
    case 'notify':
      await showNotificationSettingsDialog(context, onChanged: onChanged);
      break;
    case 'profile':
      await showBasicSettingsDialog(context, onChanged: onChanged);
      break;
  }
}

Future<void> showChangePasswordDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );
}

Future<void> showNotificationSettingsDialog(BuildContext context, {VoidCallback? onChanged}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _NotificationSettingsDialog(onChanged: onChanged),
  );
}

Future<void> showBasicSettingsDialog(BuildContext context, {VoidCallback? onChanged}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _BasicSettingsDialog(onChanged: onChanged),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = '新しいパスワードが一致しません');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthSession.instance.changePassword(
      currentPassword: _currentCtrl.text,
      newPassword: _newCtrl.text,
    );
    if (!mounted) return;
    if (err == null) {
      TextInput.finishAutofillContext(shouldSave: true);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('パスワードを変更しました')));
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('パスワード変更'),
      content: SizedBox(
        width: 360,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _currentCtrl,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: '現在のパスワード',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _newCtrl,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: '新しいパスワード（4文字以上）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: '新しいパスワード（確認）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('変更する'),
        ),
      ],
    );
  }
}

class _NotificationSettingsDialog extends StatefulWidget {
  final VoidCallback? onChanged;
  const _NotificationSettingsDialog({this.onChanged});

  @override
  State<_NotificationSettingsDialog> createState() => _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState extends State<_NotificationSettingsDialog> {
  late bool _news;
  late bool _event;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = AuthSession.instance.user;
    _news = u?.notifyNews ?? true;
    _event = u?.notifyEvent ?? true;
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthSession.instance.updateNotifications(notifyNews: _news, notifyEvent: _event);
    if (!mounted) return;
    if (err == null) {
      widget.onChanged?.call();
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('通知設定'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ニュース通知'),
              value: _news,
              onChanged: _busy ? null : (v) => setState(() => _news = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('イベント通知'),
              value: _event,
              onChanged: _busy ? null : (v) => setState(() => _event = v),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}

class _BasicSettingsDialog extends StatefulWidget {
  final VoidCallback? onChanged;
  const _BasicSettingsDialog({this.onChanged});

  @override
  State<_BasicSettingsDialog> createState() => _BasicSettingsDialogState();
}

class _BasicSettingsDialogState extends State<_BasicSettingsDialog> {
  late final TextEditingController _nickCtrl;
  late final TextEditingController _mailCtrl;
  List<Map<String, dynamic>> _teams = const [];
  List<Map<String, dynamic>> _players = const [];
  int? _teamId;
  int? _playerId;
  var _loading = true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = AuthSession.instance.user;
    _nickCtrl = TextEditingController(text: u?.nameLast ?? '');
    _mailCtrl = TextEditingController(text: u?.mailaddress ?? '');
    _teamId = u?.idTeamFav;
    _playerId = u?.idPlayerFav;
    _load();
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _mailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final teams = await AuthSession.instance.fetchTeams();
      List<Map<String, dynamic>> players = const [];
      if (_teamId != null) {
        players = await AuthSession.instance.fetchPlayers(idTeam: _teamId!);
      }
      if (!mounted) return;
      setState(() {
        _teams = teams;
        _players = players;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '読み込みに失敗しました: $e';
      });
    }
  }

  Future<void> _onTeamChanged(int? id) async {
    setState(() {
      _teamId = id;
      _playerId = null;
      _players = const [];
    });
    if (id == null) return;
    final players = await AuthSession.instance.fetchPlayers(idTeam: id);
    if (!mounted) return;
    setState(() => _players = players);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthSession.instance.updateProfile(
      nameLast: _nickCtrl.text,
      mailaddress: _mailCtrl.text,
      idTeamFav: _teamId,
      idPlayerFav: _playerId,
    );
    if (!mounted) return;
    if (err == null) {
      widget.onChanged?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('基本設定を保存しました')));
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  String _teamLabel(Map<String, dynamic> t) {
    final league = '${t['name_league'] ?? ''}'.trim();
    final name = '${t['name'] ?? ''}'.trim();
    return league.isEmpty ? name : '$league / $name';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('基本設定'),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nickCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ニックネーム',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _mailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'メールアドレス',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      value: _teams.any((t) => int.tryParse('${t['id']}') == _teamId) ? _teamId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '押しのチーム',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('未設定')),
                        for (final t in _teams)
                          if (int.tryParse('${t['id']}') != null)
                            DropdownMenuItem<int?>(
                              value: int.tryParse('${t['id']}'),
                              child: Text(_teamLabel(t), overflow: TextOverflow.ellipsis),
                            ),
                      ],
                      onChanged: _busy ? null : _onTeamChanged,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      value: _players.any((p) => int.tryParse('${p['id']}') == _playerId) ? _playerId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '押しの選手',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('未設定')),
                        for (final p in _players)
                          DropdownMenuItem<int?>(
                            value: int.tryParse('${p['id']}'),
                            child: Text('${p['name'] ?? ''}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _busy || _teamId == null ? null : (v) => setState(() => _playerId = v),
                    ),
                    if (_teamId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('選手を選ぶには先にチームを選んでください', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _busy || _loading ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}
