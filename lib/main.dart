import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// --- Path configuration ---
const String ARCHIVE_DIR = r'C:\Funktionsblatt\Archiv';
const String JSON_PATH = r'C:\Funktionsblatt\CSV_Output\output.json'; // Use a single JSON file

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Funktionsblatt PDF Export',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue)
            .copyWith(secondary: Colors.amber, error: Colors.red.shade300),
      ),
      home: const MyHomePage(title: 'Funktionsblatt PDF Export'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Map<String, dynamic>>? _bookingData;
  String? _summaryText;
  File? _jsonFile;
  String _statusMessage =
      '1. Python-Skript ausführen.\n2. Auf "Daten laden" klicken, um die JSON-Datei automatisch zu laden.';

  Future<void> _loadJsonData() async {
    setState(() => _statusMessage = "Suche nach JSON-Datei...");

    final file = File(JSON_PATH);
    if (!await file.exists()) {
      setState(() {
        _statusMessage =
            "Fehler: Konnte output.json nicht finden.\nPfad: $JSON_PATH\nStellen Sie sicher, dass das Python-Skript erfolgreich durchgelaufen ist.";
        _bookingData = null;
        _jsonFile = null;
      });
      return;
    }

    try {
      await _processJsonFile(file, isManual: false);
    } catch (e) {
      setState(() {
        _statusMessage = "Fehler beim Lesen der JSON-Datei: $e";
        _bookingData = null;
        _jsonFile = null;
      });
    }
  }

  Future<void> _pickJsonFile() async {
    setState(() => _statusMessage = "Bitte JSON-Datei manuell auswählen...");
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'output.json auswählen',
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        await _processJsonFile(file, isManual: true);
      } else {
        setState(() => _statusMessage = "Dateiauswahl abgebrochen.");
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Fehler beim manuellen Laden der JSON-Datei: $e";
        _bookingData = null;
        _jsonFile = null;
      });
    }
  }

  Future<void> _processJsonFile(File file, {bool isManual = false}) async {
    _jsonFile = file;
    final jsonString = await file.readAsString(encoding: utf8);
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    final List<dynamic> bookings = data['bookings'] ?? [];
    final String summary = data['summary'] ?? '';

    if (bookings.isEmpty) {
      setState(() {
        _statusMessage = "Keine Buchungen in der Datei gefunden.";
        _bookingData = null;
      });
    } else {
      setState(() {
        _bookingData = bookings.map((item) => Map<String, dynamic>.from(item)).toList();
        _summaryText = summary;
        final source = isManual ? "manuell ausgewählter Datei" : "Datei";
        _statusMessage =
            "${_bookingData!.length} Buchung(en) erfolgreich aus $source geladen. Bereit zum PDF-Export.";
      });
    }
  }


  Future<void> _createPdf() async {
    if (_bookingData == null || _jsonFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Keine Daten geladen. Bitte zuerst auf "1. Daten laden" klicken.')),
      );
      return;
    }

    try {
      final pdf = pw.Document();

      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);
      final baseFont = pw.TextStyle(font: ttf, fontSize: 10);
      final boldFont =
          pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10);

      // --- Date Handling ---
      DateTime bookingDate = DateTime.now(); // Fallback
      try {
        String bookingDateStr = _bookingData!.first['BookingDate'].toString();
        List<String> dateParts = bookingDateStr.split('/'); // Format is DD/MM/YYYY
        bookingDate = DateTime(int.parse(dateParts[2]), int.parse(dateParts[1]), int.parse(dateParts[0]));
      } catch (e) { /* Fallback to now() on error */ }

      const weekdayNames = ['Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag','Sonntag'];
      final formattedDate = "${weekdayNames[bookingDate.weekday - 1]}, ${bookingDate.day.toString().padLeft(2, '0')}.${bookingDate.month.toString().padLeft(2, '0')}.${bookingDate.year}";
      final safeDateFilename = "${bookingDate.year}-${bookingDate.month.toString().padLeft(2, '0')}-${bookingDate.day.toString().padLeft(2, '0')}_${weekdayNames[bookingDate.weekday - 1]}";

      // --- Header and Data Preparation ---
      // Tisch-Spalte jetzt ganz am Ende
      final List<String> pdfHeaders = ['Name', 'Typ', 'Bowling', 'Bowler', 'Resto', 'Pax', 'Notiz', 'Tisch'];

      final List<List<String>> pdfData = _bookingData!.map((booking) {
        String typeInfo = '';
        String bTypeDesc = (booking['BookingTypeDesc'] ?? '').toString().toLowerCase();
        String bType = (booking['BookingType'] ?? '').toString().toLowerCase();
        
        String notiz = (booking['Notiz'] ?? booking['Tischreservierung'] ?? '').toString();
        bool hasTable = notiz.contains('vorher') || notiz.contains('nachher');

        if (bTypeDesc.contains('kids birthday party') || bType.contains('kids birthday party') ||
            bTypeDesc.contains('kids premium') || bType.contains('kids premium')) {
          typeInfo = 'KGB';
        } else if (bTypeDesc.contains('party') || bType.contains('party')) {
          typeInfo = hasTable ? 'Buffet' : 'Party';
        } else if ((bTypeDesc.contains('family') || bType.contains('family')) && hasTable) {
          typeInfo = 'Family';
        } else if (bTypeDesc.contains('zeitbowling_resto') || bType.contains('zeitbowling_resto')) {
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

      final fileModDate = await _jsonFile!.lastModified();
      final standVomDate = "Stand vom: ${fileModDate.day.toString().padLeft(2, '0')}.${fileModDate.month.toString().padLeft(2, '0')}.${fileModDate.year} ${fileModDate.hour.toString().padLeft(2, '0')}:${fileModDate.minute.toString().padLeft(2, '0')}";

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context context) {
            return pw.Column(children: [
              pw.Text(formattedDate, style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
            ]);
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerLeft,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(standVomDate, style: pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.grey700)),
            );
          },
          build: (pw.Context context) => [
            pw.Table.fromTextArray(
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
            if (_summaryText != null && _summaryText!.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 30),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                   pw.Text("Zusammenfassung", style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                   pw.Divider(height: 10),
                   pw.Text(_summaryText!, style: baseFont),
                ])
              ),
          ],
        ),
      );

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'PDF speichern unter...',
        fileName: '$safeDateFilename.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(await pdf.save());

        await Directory(ARCHIVE_DIR).create(recursive: true);

        final String archiveJsonName = '${safeDateFilename}_output.json';
        final String archiveJsonPath = '$ARCHIVE_DIR\\$archiveJsonName';
        await _jsonFile!.rename(archiveJsonPath);

        setState(() {
          _statusMessage = "PDF erfolgreich gespeichert:\n$outputFile\n\nJSON-Datei wurde archiviert.";
          _bookingData = null;
          _summaryText = null;
          _jsonFile = null;
        });
      } else {
        setState(() {
          _statusMessage = "PDF-Speichervorgang abgebrochen.";
        });
      }
    } catch (e, s) {
      setState(() => _statusMessage = "FATALER FEHLER bei PDF-Erstellung: $e\n$s");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDataLoaded = _bookingData != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: _loadJsonData,
                icon: const Icon(Icons.download, size: 28),
                label: const Text('1. Daten laden'),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 80),
                    textStyle: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: isDataLoaded ? _createPdf : null,
                icon: const Icon(Icons.picture_as_pdf, size: 28),
                label: const Text('2. PDF erstellen'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: isDataLoaded
                        ? Theme.of(context).colorScheme.secondary
                        : Colors.grey,
                    minimumSize: const Size(double.infinity, 80),
                    textStyle: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 40),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _statusMessage.startsWith('Fehler') ||
                          _statusMessage.startsWith('FATALER')
                      ? Theme.of(context).colorScheme.error
                      : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickJsonFile,
                icon: const Icon(Icons.help_outline),
                label: const Text("Problem? JSON manuell auswählen"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
