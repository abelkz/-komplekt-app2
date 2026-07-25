import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/data_refresh.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/utils/phone_input.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../suppliers_map/domain/supplier.dart';

/// Редактор профиля компании для витрины: WhatsApp, сайт, год работы,
/// короткое описание. Телефон и название задаются при регистрации.
Future<void> showCompanyProfileSheet(BuildContext context, Supplier company) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CompanyProfileSheet(company: company),
  );
}

class _CompanyProfileSheet extends ConsumerStatefulWidget {
  const _CompanyProfileSheet({required this.company});
  final Supplier company;

  @override
  ConsumerState<_CompanyProfileSheet> createState() =>
      _CompanyProfileSheetState();
}

class _CompanyProfileSheetState extends ConsumerState<_CompanyProfileSheet> {
  late final _whatsapp =
      TextEditingController(text: widget.company.whatsapp ?? '');
  late final _website =
      TextEditingController(text: widget.company.website ?? '');
  late final _year = TextEditingController(
      text: widget.company.sinceYear?.toString() ?? '');
  late final _about = TextEditingController(text: widget.company.about ?? '');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_whatsapp, _website, _year, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final year = int.tryParse(_year.text.trim());
    if (_year.text.trim().isNotEmpty &&
        (year == null || year < 1950 || year > DateTime.now().year)) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
          content: Text('Год работы — от 1950 до ${DateTime.now().year}')));
      return;
    }
    try {
      await ref.read(supplierCabinetRepositoryProvider).saveCompanyProfile(
            whatsapp: _whatsapp.text,
            website: _website.text,
            sinceYear: year,
            about: _about.text,
          );
      refreshAppData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
          const SnackBar(content: Text('Профиль компании сохранён')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
          content:
              Text(t.startsWith('Failure: ') ? t.substring(9) : 'Ошибка')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Профиль компании',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Эти данные видит покупатель на вашей витрине.',
              style: TextStyle(fontSize: 12, color: c.gray)),
          const SizedBox(height: 16),
          _field(_whatsapp, 'WhatsApp',
              hint: '+7 700 000 0000',
              keyboard: TextInputType.phone,
              formatters: const [KzPhoneInputFormatter()]),
          const SizedBox(height: 12),
          _field(_website, 'Сайт (если есть)', hint: 'example.kz'),
          const SizedBox(height: 12),
          _field(_year, 'Год начала работы',
              hint: 'например, 2015',
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              maxLen: 4),
          const SizedBox(height: 12),
          _field(_about, 'О компании', hint: 'Чем занимаетесь, чем удобны',
              maxLines: 3),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15)),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    int? maxLen,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLines: maxLines,
      maxLength: maxLen,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
