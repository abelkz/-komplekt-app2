import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import 'auth_providers.dart';

/// Экран смены пароля после перехода по ссылке из письма восстановления.
/// Открывается автоматически, когда Supabase присылает событие
/// passwordRecovery (см. main.dart).
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_pass.text.length < 6) {
      setState(() => _error = 'Пароль — минимум 6 символов');
      return;
    }
    if (_pass.text != _pass2.text) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await ref.read(authControllerProvider.notifier).updatePassword(_pass.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Пароль обновлён')));
      context.go(Routes.home);
    } else {
      final e = ref.read(authControllerProvider).error;
      final t = e?.toString() ?? '';
      setState(() => _error =
          t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось сменить пароль');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Новый пароль')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text('Придумайте новый пароль для входа.',
              style: TextStyle(fontSize: 14, color: c.gray)),
          const SizedBox(height: 18),
          TextField(
            controller: _pass,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Новый пароль', hintText: 'минимум 6 символов'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pass2,
            obscureText: true,
            onSubmitted: (_) => _save(),
            decoration:
                const InputDecoration(labelText: 'Повторите пароль'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: c.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Сохранить пароль'),
            ),
          ),
        ],
      ),
    );
  }
}
