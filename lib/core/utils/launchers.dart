import 'package:url_launcher/url_launcher.dart';

/// Связь с продавцом: звонок, WhatsApp, сайт.
class Launchers {
  Launchers._();

  /// Звонок: tel:+77011111111
  static Future<bool> call(String phone) =>
      _open(Uri.parse('tel:${_digits(phone)}'));

  /// WhatsApp: https://wa.me/<номер>?text=...
  static Future<bool> whatsapp(String phone, {String? text}) {
    final uri = Uri.parse(
      'https://wa.me/${_digits(phone)}'
      '${text != null ? '?text=${Uri.encodeComponent(text)}' : ''}',
    );
    return _open(uri);
  }

  /// Открыть сайт поставщика во внешнем браузере.
  static Future<bool> website(String url) {
    final normalized = url.startsWith('http') ? url : 'https://$url';
    return _open(Uri.parse(normalized));
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static Future<bool> _open(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
