import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/incident.dart';
import '../utils/fmt.dart';
import 'app_store.dart';
import 'i18n.dart';

class ReportSection {
  const ReportSection(this.title, this.headers, this.rows, {this.widths});
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final List<double>? widths;
}

/// A captured report: filters and text are fixed before opening the print UI.
/// Later sensor updates or language changes cannot alter a print job's data.
class FarmReport {
  FarmReport._(this.period, this.generatedAt, this.sections);
  final String period;
  final DateTime generatedAt;
  final List<ReportSection> sections;

  factory FarmReport.capture(AppStore store,
      {required int start,
      required int end,
      required String period,
      DateTime? generatedAt}) {
    bool inRange(int time) => time >= start && time < end;
    final incidents = store.incidents.where((i) => inRange(i.ts)).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
    final resolved = incidents.where((i) => i.st == 'resolved').toList();
    final mortality = store.mortality.where((m) => inRange(m.t)).toList()
      ..sort((a, b) => b.t.compareTo(a.t));
    final harvest = store.harvest.where((h) => inRange(h.t)).toList()
      ..sort((a, b) => b.t.compareTo(a.t));
    final actions = <(Incident, IncidentRemark)>[
      for (final i in store.incidents)
        for (final r in i.rem)
          if ((r.action != null || r.died != null) && inRange(r.t)) (i, r),
    ]..sort((a, b) => b.$2.t.compareTo(a.$2.t));
    final responses = incidents.where((i) => i.actAt != null).toList();
    final recoveries =
        resolved.where((i) => i.actAt != null && i.closedAt != null).toList();
    final lost = store.mortality.fold<int>(0, (sum, m) => sum + m.n);
    String outcome(Incident i) => switch (i.st) {
          'resolved' => L('Resolved', 'Naresolba'),
          'unresolved' => L('Not resolved', 'Hindi naresolba'),
          'progress' => L('In progress', 'Kasalukuyang inaaksyunan'),
          _ => L('Open', 'Bukas'),
        };
    final date = L('Date and time', 'Petsa at oras');
    final count = L('Fish', 'Isda');
    return FarmReport._(period, generatedAt ?? DateTime.now(), [
      ReportSection(L('Overview', 'Buod'), [
        L('Measure', 'Sukatan'),
        L('Value', 'Halaga')
      ], [
        [L('Incidents', 'Mga insidente'), '${incidents.length}'],
        [L('Resolved', 'Naresolba'), '${resolved.length}'],
        [
          L('Not resolved', 'Hindi naresolba'),
          '${incidents.where((i) => i.st == 'unresolved').length}'
        ],
        [
          L('Average response', 'Karaniwang tugon'),
          responses.isEmpty
              ? '-'
              : dur((responses.fold<int>(0, (a, i) => a + i.actAt! - i.ts) /
                      responses.length)
                  .round())
        ],
        [
          L('Average recovery', 'Karaniwang pagbawi'),
          recoveries.isEmpty
              ? '-'
              : dur((recoveries.fold<int>(
                          0, (a, i) => a + i.closedAt! - i.actAt!) /
                      recoveries.length)
                  .round())
        ],
        [
          L('Fish died', 'Namatay na isda'),
          '${mortality.fold<int>(0, (a, m) => a + m.n)}'
        ],
        [
          L('Harvested fish', 'Na-harvest na isda'),
          '${harvest.fold<int>(0, (a, h) => a + h.n)}'
        ],
        [
          L('Harvest weight', 'Timbang ng harvest'),
          '${harvest.fold<double>(0, (a, h) => a + h.kg).toStringAsFixed(1)} kg'
        ],
        [
          L('Harvest value', 'Halaga ng harvest'),
          peso(harvest.fold<double>(0, (a, h) => a + h.value))
        ],
      ]),
      ReportSection(L('Water incidents', 'Mga insidente sa tubig'), [
        date,
        L('Parameter / reading', 'Parameter / reading'),
        L('Status', 'Katayuan')
      ], [
        for (final i in incidents)
          [fd(i.ts), '${i.title}\n${i.val}', outcome(i)],
      ]),
      ReportSection(L('Actions by owner', 'Mga aksyon ng may-ari'), [
        date,
        L('Action', 'Aksyon'),
        L('Incident', 'Insidente')
      ], [
        for (final (i, r) in actions)
          [
            fd(r.t),
            r.action ?? '${L('Fish died', 'Namatay na isda')}: ${r.died}',
            '${i.title} (${i.val})'
          ],
      ]),
      ReportSection(L('Fish mortality', 'Mga namatay na isda'), [
        date,
        count,
        L('Suspected cause / recorded readings',
            'Posibleng sanhi / naitalang readings')
      ], [
        for (final m in mortality)
          [
            fd(m.t),
            '${m.n}',
            '${m.cause}${m.snap.isEmpty ? '' : '\n${m.snap}'}'
          ],
      ], widths: const [
        1.15,
        .35,
        2.5
      ]),
      ReportSection(L('Harvest', 'Harvest (pag-ani)'), [
        date,
        count,
        'kg',
        L('Value', 'Halaga')
      ], [
        for (final h in harvest)
          [fd(h.t), '${h.n}', h.kg.toStringAsFixed(1), peso(h.value)],
      ]),
      ReportSection(
          L('Production summary - cycle to date',
              'Buod ng produksyon - buong cycle'),
          [
            L('Measure', 'Sukatan'),
            L('Value', 'Halaga')
          ],
          [
            [
              L('Fingerlings stocked', 'Inilagay na fingerlings'),
              '${store.stock.n}'
            ],
            [L('Pond area', 'Lawak ng palaisdaan'), '${store.stock.area} m²'],
            [L('Date stocked', 'Petsa ng stocking'), store.stock.date],
            [L('Total fish died', 'Kabuuang namatay'), '$lost'],
            [
              L('Total harvested fish', 'Kabuuang na-harvest'),
              '${store.harvest.fold<int>(0, (a, h) => a + h.n)}'
            ],
            [L('Fish remaining', 'Natitirang isda'), '${store.aliveCount}'],
            [
              L('Survival rate', 'Porsyento ng nabuhay'),
              store.stock.n > 0
                  ? '${((store.stock.n - lost) / store.stock.n * 100).clamp(0, 100).round()}%'
                  : '-'
            ],
            [
              L('Total harvest weight', 'Kabuuang timbang ng harvest'),
              '${store.harvest.fold<double>(0, (a, h) => a + h.kg).toStringAsFixed(1)} kg'
            ],
            [
              L('Total harvest value', 'Kabuuang halaga ng harvest'),
              peso(store.harvest.fold<double>(0, (a, h) => a + h.value))
            ],
          ]),
    ]);
  }

  String get text => [
        'LIPONHAY FISH FARM - AquaWatch',
        'Pond 1 · Tilapia',
        period,
        'Generated: ${DateFormat('MMM d, y · h:mm a').format(generatedAt)}',
        for (final section in sections) ...[
          '',
          section.title.toUpperCase(),
          section.headers.join(' | '),
          if (section.rows.isEmpty) '-',
          for (final row in section.rows) row.join(' | '),
        ],
      ].join('\n');
}

class ReportService {
  static List<String> _chunks(String text) {
    final chunks = <String>[];
    var rest = text.runes.toList();
    while (rest.length > 360) {
      final candidate = String.fromCharCodes(rest.take(360));
      final space = candidate.lastIndexOf(RegExp(r'\s'));
      final part = space > candidate.length ~/ 2
          ? candidate.substring(0, space + 1)
          : candidate;
      chunks.add(part);
      rest = rest.skip(part.runes.length).toList();
    }
    chunks.add(String.fromCharCodes(rest));
    return chunks;
  }

  // Table rows cannot span pages. Preserve long notes in continuation rows.
  static List<List<String>> _printRows(List<List<String>> rows) {
    final result = <List<String>>[];
    for (final row in rows) {
      final cells = [for (final cell in row) _chunks(cell)];
      final parts = cells.fold<int>(
          1, (count, cell) => count > cell.length ? count : cell.length);
      for (var part = 0; part < parts; part++) {
        result.add([
          for (final cell in cells) part < cell.length ? cell[part] : '',
        ]);
      }
    }
    return result;
  }

  /// Fonts are bundled, so PDF creation requires no internet connection.
  static Future<Uint8List> buildPdf(FarmReport report,
      {PdfPageFormat format = PdfPageFormat.a4}) async {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
    final teal = PdfColor.fromHex('#0F4C5C');
    final document = pw.Document(
        title: 'AquaWatch - ${report.period}', author: 'Liponhay Fish Farm');
    List<pw.Widget> sectionContent(ReportSection section) => [
          pw.Header(
              level: 1,
              text: section.title,
              textStyle: pw.TextStyle(fontSize: 12, color: teal)),
          if (section.rows.isEmpty)
            pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text('-', style: const pw.TextStyle(fontSize: 9)))
          else
            pw.TableHelper.fromTextArray(
              headers: section.headers,
              data: _printRows(section.rows),
              columnWidths: {
                for (var i = 0; i < section.headers.length; i++)
                  i: pw.FlexColumnWidth((section.widths ??
                      (section.headers.length == 2
                          ? [3.0, 2.0]
                          : section.headers.length == 3
                              ? [1.15, 1.85, 1.0]
                              : [1.6, .6, .7, 1.0]))[i]),
              },
              headerDecoration: pw.BoxDecoration(color: teal),
              headerStyle:
                  pw.TextStyle(color: PdfColors.white, font: font, fontSize: 9),
              cellStyle: pw.TextStyle(font: font, fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(7),
              cellAlignment: pw.Alignment.topLeft,
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey100),
              border: const pw.TableBorder(
                  horizontalInside:
                      pw.BorderSide(color: PdfColors.grey300, width: .3)),
            ),
          pw.SizedBox(height: 10),
        ];
    document.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(32),
      maxPages: 1000,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (context) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: teal, width: 1.5))),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('LIPONHAY FISH FARM',
                  style: pw.TextStyle(fontSize: 17, color: teal)),
              pw.Text('AquaWatch · Pond 1 · Tilapia',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 6),
              pw.Text(report.period, style: const pw.TextStyle(fontSize: 11)),
            ]),
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                  'Generated: ${DateFormat('MMM d, y · h:mm a').format(report.generatedAt)}',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8)),
            ]),
      ),
      build: (context) => [
        for (final section in report.sections)
          if (section == report.sections.last && format.height >= 600)
            pw.Inseparable(child: pw.Column(children: sectionContent(section)))
          else
            ...sectionContent(section),
      ],
    ));
    return document.save();
  }

  static Future<bool> printReport(FarmReport report) => Printing.layoutPdf(
        name: 'AquaWatch-${report.generatedAt.millisecondsSinceEpoch}.pdf',
        format: PdfPageFormat.a4,
        onLayout: (format) => buildPdf(report, format: format),
      );
}
