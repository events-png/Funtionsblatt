import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'xml_import.dart';

Future<Uint8List> createSheetPdf(
  FunctionSheet sheet,
  DateTime sourceModified,
  ByteData fontData,
) async {
  final pdf = pw.Document();

  final ttf = pw.Font.ttf(fontData);
  final baseFont = pw.TextStyle(font: ttf, fontSize: 10);
  final boldFont = pw.TextStyle(
    font: ttf,
    fontWeight: pw.FontWeight.bold,
    fontSize: 10,
  );

  // --- Date Handling ---
  final bookingDate = sheet.date;

  const weekdayNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  final formattedDate =
      "${weekdayNames[bookingDate.weekday - 1]}, ${bookingDate.day.toString().padLeft(2, '0')}.${bookingDate.month.toString().padLeft(2, '0')}.${bookingDate.year}";

  // --- Header and Data Preparation ---
  // Tisch-Spalte jetzt ganz am Ende
  final List<String> pdfHeaders = [
    'Name',
    'Typ',
    'Bowling',
    'Bowler',
    'Resto',
    'Pax',
    'Notiz',
    'Tisch',
  ];

  final List<List<String>> pdfData = sheet.bookings.map((booking) {
    String typeInfo = '';
    String bTypeDesc = (booking['BookingTypeDesc'] ?? '')
        .toString()
        .toLowerCase();
    String bType = (booking['BookingType'] ?? '').toString().toLowerCase();

    String notiz = (booking['Notiz'] ?? booking['Tischreservierung'] ?? '')
        .toString();
    bool hasTable = notiz.contains('vorher') || notiz.contains('nachher');

    if (bTypeDesc.contains('kids birthday party') ||
        bType.contains('kids birthday party') ||
        bTypeDesc.contains('kids premium') ||
        bType.contains('kids premium')) {
      typeInfo = 'KGB';
    } else if (bTypeDesc.contains('party') || bType.contains('party')) {
      typeInfo = hasTable ? 'Buffet' : 'Party';
    } else if ((bTypeDesc.contains('family') || bType.contains('family')) &&
        hasTable) {
      typeInfo = 'Family';
    } else if (bTypeDesc.contains('zeitbowling_resto') ||
        bType.contains('zeitbowling_resto')) {
      typeInfo = 'Bowl&Eat';
    }

    String bVal = (booking['Bowler'] ?? '0').toString();
    String pVal = (booking['Pax'] ?? '0').toString();

    String displayBowler = (bVal == '0' || bVal.trim().isEmpty) ? pVal : bVal;
    String displayPax = (pVal == '0' || pVal.trim().isEmpty) ? bVal : pVal;

    return [
      booking['Name']?.toString() ?? '',
      typeInfo,
      booking['Bowlinguhrzeit']?.toString() ?? '',
      displayBowler,
      booking['Resto']?.toString() ?? '',
      displayPax,
      notiz,
      '', // Leere Tisch-Spalte am Ende (Index 7)
    ];
  }).toList();

  final fileModDate = sourceModified;
  final standVomDate =
      "Stand vom: ${fileModDate.day.toString().padLeft(2, '0')}.${fileModDate.month.toString().padLeft(2, '0')}.${fileModDate.year} ${fileModDate.hour.toString().padLeft(2, '0')}:${fileModDate.minute.toString().padLeft(2, '0')}";

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Text(
              formattedDate,
              style: pw.TextStyle(
                font: ttf,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 20),
          ],
        );
      },
      footer: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.centerLeft,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            standVomDate,
            style: pw.TextStyle(
              font: ttf,
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        );
      },
      build: (pw.Context context) => [
        pw.TableHelper.fromTextArray(
          headers: pdfHeaders,
          data: pdfData,
          border: pw.TableBorder.all(),
          headerStyle: boldFont,
          cellStyle: baseFont,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2), // Name
            1: pw.FlexColumnWidth(1.4), // Typ
            2: pw.FlexColumnWidth(1.1), // Bowling
            3: pw.FlexColumnWidth(1.0), // Bowler
            4: pw.FlexColumnWidth(1.0), // Resto
            5: pw.FlexColumnWidth(0.6), // Pax
            6: pw.FlexColumnWidth(3.2), // Notiz
            7: pw.FlexColumnWidth(0.8), // Tisch
          },
          cellAlignments: {
            0: pw.Alignment.topLeft,
            1: pw.Alignment.topLeft,
            2: pw.Alignment.topLeft,
            3: pw.Alignment.topCenter, // Bowler zentriert
            4: pw.Alignment.topLeft,
            5: pw.Alignment.topCenter, // Pax zentriert
            6: pw.Alignment.topLeft,
            7: pw.Alignment.topLeft,
          },
        ),
        if (sheet.summary.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 30),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Zusammenfassung",
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Divider(height: 10),
                pw.Text(sheet.summary, style: baseFont),
              ],
            ),
          ),
      ],
    ),
  );

  return pdf.save();
}
