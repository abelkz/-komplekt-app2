import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Полноэкранный ввод одной строки (название подборки и т.п.).
///
/// Диалоги с полем на iOS-вебе «уезжают» под клавиатуру (Safari прокручивает
/// страницу). Полноэкранная страница ведёт себя правильно на всех платформах.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String hint = '',
  String initial = '',
  String action = 'Сохранить',
}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TextEntryPage(
      title: title,
      label: label,
      hint: hint,
      initial: initial,
      action: action,
    ),
  ));
}

class _TextEntryPage extends StatefulWidget {
  const _TextEntryPage({
    required this.title,
    required this.label,
    required this.hint,
    required this.initial,
    required this.action,
  });

  final String title;
  final String label;
  final String hint;
  final String initial;
  final String action;

  @override
  State<_TextEntryPage> createState() => _TextEntryPageState();
}

class _TextEntryPageState extends State<_TextEntryPage> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _save,
              child: Text(widget.action),
            ),
          ),
        ],
      ),
    );
  }
}
