import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';

/// Универсальная обёртка для состояний loading / error / empty / data.
/// Используется на всех экранах, чтобы единообразно показывать состояния.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.isEmpty,
    this.empty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const _CenterLoader(),
      error: (e, _) => _ErrorState(message: _msg(e), onRetry: onRetry),
      data: (d) {
        if (isEmpty != null && isEmpty!(d)) {
          return empty ?? const EmptyState(title: 'Пока пусто');
        }
        return data(d);
      },
    );
  }

  String _msg(Object e) {
    final t = e.toString();
    return t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось загрузить';
  }
}

class _CenterLoader extends StatelessWidget {
  const _CenterLoader();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text('Ошибка',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 5),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.gray)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Пустое состояние (нет данных) — переиспользуется на многих экранах.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15, color: c.ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.gray)),
            ],
          ],
        ),
      ),
    );
  }
}
