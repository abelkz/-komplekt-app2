import 'package:flutter/material.dart';

/// Экран на случай, когда приложение не смогло подняться: Supabase не
/// ответил, ключи не прочитались, сеть недоступна.
///
/// Раньше такой сбой означал чёрный экран: исключение вылетало из `main()`
/// до `runApp`, и человек видел пустоту без единого слова. Теперь он видит
/// причину и кнопку «Повторить».
///
/// Намеренно не использует ни AppTheme, ни Riverpod, ни шрифты из сети —
/// на этом этапе ещё ничего не инициализировано, и любая лишняя зависимость
/// может упасть следом.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.onRetry, this.details});

  /// Повторная попытка запуска.
  final VoidCallback onRetry;

  /// Техническая причина — мелким шрифтом, чтобы можно было прислать в
  /// поддержку скриншотом.
  final String? details;

  static const _paper = Color(0xFF121414);
  static const _card = Color(0xFF1E2020);
  static const _ink = Color(0xFFE3E2E2);
  static const _gray = Color(0xFFD4C5AB);
  static const _yellow = Color(0xFFFABD00);
  static const _brandInk = Color(0xFF241A00);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 44, color: _gray),
                  const SizedBox(height: 18),
                  const Text(
                    'Не удалось подключиться',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Сервис временно недоступен. Проверьте интернет и '
                    'попробуйте ещё раз — данные никуда не пропали.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _gray, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: _yellow,
                      foregroundColor: _brandInk,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                    ),
                    child: const Text('Повторить'),
                  ),
                  if (details != null) ...[
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        details!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _gray, fontSize: 11, height: 1.35),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
