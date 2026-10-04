import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/auth_session.dart';

const _openRegister = Object();

Future<bool> showLoginDialog(BuildContext context) async {
  while (context.mounted) {
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _LoginDialog(),
    );
    if (!context.mounted) return AuthSession.instance.isLoggedIn;
    if (identical(result, _openRegister)) {
      final registered = await showRegisterDialog(context);
      if (registered || AuthSession.instance.isLoggedIn) return true;
      continue;
    }
    return result == true || AuthSession.instance.isLoggedIn;
  }
  return AuthSession.instance.isLoggedIn;
}

Future<bool> showRegisterDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _RegisterDialog(),
  );
  return ok == true;
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthSession.instance.login(
      login: _loginCtrl.text,
      password: _passCtrl.text,
    );
    if (!mounted) return;
    if (err == null) {
      TextInput.finishAutofillContext(shouldSave: true);
      Navigator.of(context).pop(true);
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
      title: const Text('ログイン'),
      content: SizedBox(
        width: 340,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _loginCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'メールアドレスまたはユーザーID',
                  hintText: '例: name@example.com / @user_id',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'パスワード',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ログイン'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(_openRegister),
                child: const Text('新規ユーザー登録する方はこちら'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog();

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _mailCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _mailCtrl.dispose();
    _handleCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthSession.instance.register(
      mailaddress: _mailCtrl.text,
      nameHandle: _handleCtrl.text,
      password: _passCtrl.text,
    );
    if (!mounted) return;
    if (err == null) {
      TextInput.finishAutofillContext(shouldSave: true);
      Navigator.of(context).pop(true);
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
      title: const Text('新規ユーザー登録'),
      content: SizedBox(
        width: 340,
        child: AutofillGroup(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _mailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _handleCtrl,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'ユーザーID',
                    hintText: '半角英数字（先頭の@は任意）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'パスワード（4文字以上）',
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('登録する'),
        ),
      ],
    );
  }
}
