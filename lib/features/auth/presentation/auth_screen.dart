import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_input.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/tape_stripe.dart';
import '../data/auth_repository.dart';
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
  final _otp = TextEditingController(); // задел под SMS-код, когда подключим провайдера

  // ignore: unused_field
  bool _otpSent = false; // пригодится, когда появится SMS/WhatsApp-провайдер
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
                            // Сразу показываем «+7 7» — остаётся дописать номер
                            if (_phone.text.isEmpty) {
                              _phone.text = KzPhoneInputFormatter.initial;
                            }
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
                                    strokeWidth: 2, color: AppColors.brandInk))
                            : Text(_primaryLabel()),
                      ),
                    ),

                    // ── Вход через Google / Apple ──
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(child: Divider(color: c.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('ИЛИ',
                              style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: c.gray)),
                        ),
                        Expanded(child: Divider(color: c.line)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ProviderButton(
                      label: 'Продолжить с Google',
                      icon: const _GoogleMark(),
                      onTap: loading
                          ? null
                          : () => _oauth(OAuthProvider.google),
                    ),
                    const SizedBox(height: 10),
                    _ProviderButton(
                      label: 'Продолжить с Apple',
                      icon: Icon(Icons.apple, size: 20, color: c.ink),
                      onTap: loading
                          ? null
                          : () => _oauth(OAuthProvider.apple),
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

  /// Переключатель Вход / Регистрация — общий для обоих способов входа.
  Widget _modeSwitch(AppColors c) => Container(
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
              onTap: () => setState(() {
                _mode = _Mode.login;
                _error = null;
              }),
            ),
            _Segment(
              label: 'Регистрация',
              selected: _mode == _Mode.register,
              onTap: () => setState(() {
                _mode = _Mode.register;
                _error = null;
              }),
            ),
          ],
        ),
      );

  // ── Форма email ──
  List<Widget> _emailForm(AppColors c) => [
        _modeSwitch(c),
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

  // ── Форма телефона ──
  // Вход по номеру и паролю, без SMS: номер превращается в служебный email
  // <11 цифр>@example.com. Ровно так же работает веб-кабинет поставщика,
  // поэтому аккаунт один и тот же в приложении и на supplier.html.
  List<Widget> _phoneForm(AppColors c) => [
        _modeSwitch(c),
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
        _label('Телефон'),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: const [KzPhoneInputFormatter()],
          onTap: () {
            // Если поле пустое — сразу ставим «+7 7», чтобы не набирать код
            if (_phone.text.isEmpty) {
              _phone.text = KzPhoneInputFormatter.initial;
            }
          },
          decoration: const InputDecoration(hintText: '+7 700 000 0000'),
        ),
        const SizedBox(height: 14),
        _label('Пароль'),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'минимум 6 символов'),
        ),
        const SizedBox(height: 8),
        Text(
          'Код в SMS не приходит — вход по номеру и паролю. '
          'Тот же аккаунт работает в кабинете поставщика на сайте.',
          style: TextStyle(fontSize: 12, color: c.faint, height: 1.35),
        ),
      ];

  String _primaryLabel() =>
      _mode == _Mode.login ? 'Войти' : 'Зарегистрироваться';

  Future<void> _submit() async {
    setState(() => _error = null);
    final ctrl = ref.read(authControllerProvider.notifier);
    final city = ref.read(settingsProvider).city;

    // По какому логину входим: обычный email или служебный из номера
    final String login;
    if (_method == _Method.phone) {
      final mapped = AuthRepository.phoneToEmail(_phone.text);
      if (mapped == null) {
        setState(() =>
            _error = 'Укажите номер в формате +7 7XX XXX XX XX');
        return;
      }
      login = mapped;
    } else {
      login = _email.text.trim();
      if (!login.contains('@')) {
        setState(() => _error = 'Укажите корректный email');
        return;
      }
    }
    if (_pass.text.length < 6) {
      setState(() => _error = 'Пароль должен быть не короче 6 символов');
      return;
    }

    bool ok;
    if (_mode == _Mode.register) {
      ok = await ctrl.signUp(
        email: login,
        password: _pass.text,
        fullName: _name.text.trim(),
        city: city,
        phone: _phone.text.trim(),
      );
      // Сразу входим (если в Supabase отключено подтверждение email)
      if (ok) ok = await ctrl.signIn(login, _pass.text);
    } else {
      ok = await ctrl.signIn(login, _pass.text);
    }

    if (!ok && mounted) {
      final err = ref.read(authControllerProvider).error;
      setState(() => _error = err is Object ? _msg(err) : 'Не удалось');
    }
    // При успехе redirect в роутере сам переведёт на главную.
  }

  /// Вход через внешнего провайдера (Google / Apple).
  Future<void> _oauth(OAuthProvider provider) async {
    setState(() => _error = null);
    final ok =
        await ref.read(authControllerProvider.notifier).signInWithProvider(provider);
    if (!ok && mounted) {
      final err = ref.read(authControllerProvider).error;
      setState(() => _error = err is Object ? _msg(err) : 'Не удалось войти');
    }
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

/// Кнопка входа через внешнего провайдера.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: c.line),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

/// Фирменная разноцветная «G» — нарисована кодом, без картинок в ассетах.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: CustomPaint(painter: _GooglePainter()),
      );
}

class _GooglePainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.22;
    final arc = Rect.fromCircle(
        center: rect.center, radius: (size.width - stroke) / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // четыре дуги по 90° в фирменных цветах
    canvas.drawArc(arc, -0.35, 1.25, false, p..color = _blue);
    canvas.drawArc(arc, 0.95, 1.35, false, p..color = _green);
    canvas.drawArc(arc, 2.35, 1.35, false, p..color = _yellow);
    canvas.drawArc(arc, 3.75, 1.55, false, p..color = _red);

    // перекладина буквы G
    canvas.drawLine(
      Offset(size.width * 0.52, size.height / 2),
      Offset(size.width * 0.98, size.height / 2),
      Paint()
        ..color = _blue
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
