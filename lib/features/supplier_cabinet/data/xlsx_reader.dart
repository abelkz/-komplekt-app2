import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Простой и терпимый читатель .xlsx.
///
/// Пакет `excel` разбирает файл целиком, включая оформление, и на прайсах
/// из реальных программ падает с «Damaged Excel file: styles» — хотя данные
/// в файле в порядке. Нам оформление не нужно: достаточно текста ячеек.
///
/// Читаем только то, что нужно: общий словарь строк и первый лист.
/// Формулы берём по последнему вычисленному значению, даты оставляем
/// числом — для прайса важны название, цена и артикул.
class XlsxReader {
  XlsxReader._();

  /// Возвращает таблицу строк (первая строка — заголовки).
  /// Бросает [FormatException], если это не похоже на xlsx.
  static List<List<String>> read(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Файл не похож на .xlsx');
    }

    String? fileText(String path) {
      for (final f in archive.files) {
        if (f.name == path && f.isFile) {
          return utf8.decode(f.content as List<int>, allowMalformed: true);
        }
      }
      return null;
    }

    // 1. Общий словарь строк: ячейки типа "s" ссылаются на него по номеру
    final shared = <String>[];
    final sharedXml = fileText('xl/sharedStrings.xml');
    if (sharedXml != null) {
      for (final si in XmlDocument.parse(sharedXml).findAllElements('si')) {
        // текст может быть разбит на несколько кусков <t> с разным оформлением
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    // 2. Первый лист книги
    final sheetXml = _firstSheet(archive, fileText);
    if (sheetXml == null) {
      throw const FormatException('В книге не нашлось ни одного листа');
    }

    final doc = XmlDocument.parse(sheetXml);
    final table = <int, Map<int, String>>{};
    var maxCol = 0;

    for (final row in doc.findAllElements('row')) {
      final rowIndex = int.tryParse(row.getAttribute('r') ?? '') ?? (table.length + 1);
      final cells = <int, String>{};
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r') ?? '';
        final col = _columnIndex(ref);
        if (col < 0) continue;
        final value = _cellText(c, shared);
        if (value.isNotEmpty) {
          cells[col] = value;
          if (col > maxCol) maxCol = col;
        }
      }
      if (cells.isNotEmpty) table[rowIndex] = cells;
    }

    if (table.isEmpty) return const [];

    final rowNumbers = table.keys.toList()..sort();
    return [
      for (final n in rowNumbers)
        [
          for (var col = 0; col <= maxCol; col++) table[n]![col] ?? '',
        ],
    ];
  }

  /// Первый лист: сначала пробуем sheet1.xml, потом любой из worksheets.
  static String? _firstSheet(
      Archive archive, String? Function(String) fileText) {
    final direct = fileText('xl/worksheets/sheet1.xml');
    if (direct != null) return direct;
    for (final f in archive.files) {
      if (f.isFile &&
          f.name.startsWith('xl/worksheets/') &&
          f.name.endsWith('.xml')) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  /// Текст ячейки с учётом её типа.
  static String _cellText(XmlElement c, List<String> shared) {
    final type = c.getAttribute('t');
    if (type == 'inlineStr') {
      return c.findAllElements('t').map((t) => t.innerText).join().trim();
    }
    final v = c.findElements('v').firstOrNull?.innerText.trim() ?? '';
    if (v.isEmpty) return '';
    if (type == 's') {
      final idx = int.tryParse(v);
      if (idx != null && idx >= 0 && idx < shared.length) {
        return shared[idx].trim();
      }
      return '';
    }
    return v;
  }

  /// «C7» → 2 (нумерация колонок с нуля). Возвращает -1, если не разобрали.
  static int _columnIndex(String ref) {
    var col = 0;
    var seen = false;
    for (final code in ref.codeUnits) {
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
        seen = true;
      } else if (code >= 97 && code <= 122) {
        col = col * 26 + (code - 96);
        seen = true;
      } else {
        break;
      }
    }
    return seen ? col - 1 : -1;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
