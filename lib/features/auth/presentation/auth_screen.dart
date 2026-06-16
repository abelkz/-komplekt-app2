import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/tape_stripe.dart';
import 'auth_providers.dart';

/// Экран 2 — авторизация: email (вход/регистрация) или телефон (SMS-код).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { login, register }

enum _Method { email, phone }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  _Mode _mode = _Mode.login;
  _Method _method = _Method.email;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _otpSent = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _pass, _phone, _otp]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      body: Column(
        children: [
          const TapeStripe(),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('КОМПЛЕКТ', style: AppTypography.unbounded(size: 24)),
                    const SizedBox(height: 6),
                    Text('Вход в приложение',
                        style: TextStyle(color: c.gray, fontSize: 13)),
                    const SizedBox(height: 22),

                    // Способ входа: email / телефон
                    Row(
                      children: [
                        _MethodChip(
                          label: 'По email',
                          selected: _method == _Method.email,
                          onTap: () => setState(() {
                            _method = _Method.email;
                            _error = null;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _MethodChip(
                          label: 'По телефону',
                          selected: _method == _Method.phone,
                          onTap: () => setState(() {
                            _method = _Method.phone;
                            _error = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    if (_method == _Method.email)
                      ..._emailForm(c)
                    else
                      ..._phoneForm(c),

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorBox(_error!),
                    ],

                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(_primaryLabel()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Форма email ──
  List<Widget> _emailForm(AppColors c) => [
        // переключатель Вход / Регистрация
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              _Segment(
                label: 'Вход',
                selected: _mode == _Mode.login,
                onTap: () => setState(() => _mode = _Mode.login),
              ),
              _Segment(
                label: 'Регистрация',
                selected: _mode == _Mode.register,
                onTap: () => setState(() => _mode = _Mode.register),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_mode == _Mode.register) ...[
          _label('Имя'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Имя Фамилия'),
          ),
          const SizedBox(height: 14),
        ],
        _label('Email'),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'you@mail.kz'),
        ),
        const SizedBox(height: 14),
        _label('Пароль'),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'минимум 6 символов'),
        ),
      ];

  // ── Форма телефона (SMS-код) ──
  List<Widget> _phoneForm(AppColors c) => [
        _label('Телефон'),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          enabled: !_otpSent,
          decoration: const InputDecoration(hintText: '+7 7XX XXX XX XX'),
        ),
        if (_otpSent) ...[
          const SizedBox(height: 14),
          _label('Код из SMS'),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '6 цифр'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _otpSent = false),
            child: const Text('Изменить номер'),
          ),
        ],
      ];

  String _primaryLabel() {
    if (_method == _Method.phone) {
      return _otpSent ? 'Подтвердить код' : 'Получить код';
    }
    return _mode == _Mode.login ? 'Войти' : 'Зарегистрироваться';
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final ctrl = ref.read(authControllerProvider.notifier);
    final city = ref.read(settingsProvider).city;

    bool ok;
    if (_method == _Method.phone) {
      final phone = _phone.text.trim();
      if (!_otpSent) {
        ok = await ctrl.sendOtp(phone);
        if (ok) setState(() => _otpSent = true);
      } else {
        ok = await ctrl.verifyOtp(phone, _otp.text.trim());
      }
    } else if (_mode == _Mode.register) {
      ok = await ctrl.signUp(
        email: _email.text.trim(),
        password: _pass.text,
        fullName: _name.text.trim(),
        city: city,
        phone: _phone.text.trim(),
      );
      // Сразу входим (если в Supabase отключено подтверждение email)
      if (ok) ok = await ctrl.signIn(_email.text.trim(), _pass.text);
    } else {
      ok = await ctrl.signIn(_email.text.trim(), _pass.text);
    }

    if (!ok && mounted) {
      final err = ref.read(authControllerProvider).error;
      setState(() => _error = err is Object ? _msg(err) : 'Не удалось');
    }
    // При успехе redirect в роутере сам переведёт на главную.
  }

  String _msg(Object e) {
    final t = e.toString();
    return t.startsWith('Failure: ') ? t.substring(9) : t;
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: context.colors.gray)),
      );
}

class _MethodChip extends StatelessWidget {
  const _MethodChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.ink : c.card,
            border: Border.all(color: selected ? c.ink : c.line),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? c.paper : c.ink)),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? c.paper : c.gray)),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.redSoft, borderRadius: BorderRadius.circular(AppRadii.sm)),
      child: Text(message, style: TextStyle(color: c.red, fontSize: 13)),
    );
  }
}
