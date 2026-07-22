// universal_io вместо dart:io: на мобильных это тот же dart:io,
// но код компилируется и для веба (там файловые операции не используются).
import 'dart:ui' show Rect;

import 'package:universal_io/io.dart';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../domain/collection.dart';

/// Экспорт спецификации подборки в Excel и PDF.
/// Цены берутся по лучшему (самому дешёвому) предложению каждого товара.
class SpecExport {
  SpecExport._();

  /// Строки спецификации: №, наименование, артикул, поставщик, цена, кол-во, ед., сумма.
  static List<_Row> _rows(Collection c) {
    final items = c.items.where((i) => i.product != null).toList();
    return [
      for (var i = 0; i < items.length; i++)
        () {
          final it = items[i];
          final p = it.product!;
          final best = p.bestOffer;
          return _Row(
            n: i + 1,
            name: p.name,
            sku: p.sku,
            supplier: best?.supplierName ?? '',
            price: best?.price ?? 0,
            qty: it.qty,
            unit: p.unit,
            sum: (best?.price ?? 0) * it.qty,
          );
        }(),
    ];
  }

  static String _fileBase(Collection c) {
    final date = DateTime.now();
    final d = '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
    return 'Спецификация ${c.name} $d'
        .replaceAll(RegExp(r'[\\/:*?"<>|·]'), '-');
  }

  // ───────────────────────── Excel ─────────────────────────
  /// [shareOrigin] — прямоугольник-источник для системного «Поделиться».
  /// На iPad меню показывается поповером и без него UIKit роняет приложение;
  /// на iPhone и Android параметр игнорируется.
  static Future<void> exportExcel(Collection c, {Rect? shareOrigin}) async {
    final rows = _rows(c);
    final excel = Excel.createExcel();
    const sheetName = 'Спецификация';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    // убираем пустой лист по умолчанию
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    sheet.appendRow([TextCellValue('Спецификация: ${c.name}')]);
    sheet.appendRow([
      TextCellValue('Дата: ${_fileBase(c).split(' ').last} · КОМПЛЕКТ'),
    ]);
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('№'),
      TextCellValue('Наименование'),
      TextCellValue('Артикул'),
      TextCellValue('Поставщик'),
      TextCellValue('Цена, ₸'),
      TextCellValue('Кол-во'),
      TextCellValue('Ед.'),
      TextCellValue('Сумма, ₸'),
    ]);
    for (final r in rows) {
      sheet.appendRow([
        IntCellValue(r.n),
        TextCellValue(r.name),
        TextCellValue(r.sku),
        TextCellValue(r.supplier),
        DoubleCellValue(r.price),
        DoubleCellValue(r.qty),
        TextCellValue(r.unit),
        DoubleCellValue(r.sum),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Итого:'),
      DoubleCellValue(c.total),
    ]);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Не удалось сформировать Excel');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileBase(c)}.xlsx');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Спецификация «${c.name}»',
      sharePositionOrigin: shareOrigin,
    );
  }

  // ───────────────────────── PDF ─────────────────────────
  /// [shareOrigin] — см. комментарий у [exportExcel] (поповер на iPad).
  static Future<void> exportPdf(Collection c, {Rect? shareOrigin}) async {
    final rows = _rows(c);
    // Шрифты Open Sans поддерживают кириллицу
    final regular = await PdfGoogleFonts.openSansRegular();
    final bold = await PdfGoogleFonts.openSansBold();

    final doc = pw.Document();
    const orange = PdfColor.fromInt(0xFFE8490D);
    const grayInt = 0xFF6B6F6D;

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          margin: const pw.EdgeInsets.all(36),
        ),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('КОМПЛЕКТ',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 15,
                      color: orange)),
              pw.Text(_fileBase(c).split(' ').last,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColor.fromInt(grayInt))),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('Спецификация · ${c.name}',
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text('Цены — лучшие предложения поставщиков на дату формирования',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColor.fromInt(grayInt))),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1EFEC)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(18),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(60),
              3: const pw.FixedColumnWidth(72),
              4: const pw.FixedColumnWidth(48),
              5: const pw.FixedColumnWidth(34),
              6: const pw.FixedColumnWidth(24),
              7: const pw.FixedColumnWidth(54),
            },
            data: [
              ['№', 'Наименование', 'Артикул', 'Поставщик', 'Цена, ₸', 'Кол-во', 'Ед.', 'Сумма, ₸'],
              for (final r in rows)
                [
                  '${r.n}',
                  r.name,
                  r.sku,
                  r.supplier,
                  // Цены нет — в таблице спецификации ставим прочерк
                  r.price > 0 ? Formatters.number(r.price) : '—',
                  Formatters.number(r.qty),
                  r.unit,
                  r.sum > 0 ? Formatters.number(r.sum) : '—',
                ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Итого: ${Formatters.price(c.total)}',
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Сформировано в приложении КОМПЛЕКТ · цены могли измениться, '
            'актуальность уточняйте у поставщика',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColor.fromInt(0xFF9B9893)),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_fileBase(c)}.pdf',
      bounds: shareOrigin,
    );
  }
}

class _Row {
  _Row({
    required this.n,
    required this.name,
    required this.sku,
    required this.supplier,
    required this.price,
    required this.qty,
    required this.unit,
    required this.sum,
  });
  final int n;
  final String name;
  final String sku;
  final String supplier;
  final double price;
  final double qty;
  final String unit;
  final double sum;
}
