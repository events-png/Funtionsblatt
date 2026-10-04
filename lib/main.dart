import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'batch_export.dart';
import 'pdf_export.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Funktionsblatt PDF Export',
    theme: ThemeData(colorSchemeSeed: Colors.blue),
    home: const ExportPage(),
  );
}

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  String _input = r'C:\Funktionsblatt';
  String _output = r'C:\Funktionsblatt\PDF_Output';
  String _status =
      'XML-Dateien exportieren und anschließend auf „Funktionsblätter erstellen“ klicken.';
  bool _busy = true;
  File? _settingsFile;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _settingsFile = File(p.join(dir.path, 'export_settings.json'));
      if (await _settingsFile!.exists()) {
        final settings = jsonDecode(
          await _settingsFile!.readAsString(),
        ) as Map<String, dynamic>;
        _input = settings['input'] as String? ?? _input;
        _output = settings['output'] as String? ?? _output;
      }
    } catch (e) {
      _status = 'Ordner-Einstellungen konnten nicht geladen werden: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickFolder(bool input) async {
    setState(() => _busy = true);
    try {
      final folder = await FilePicker.platform.getDirectoryPath(
        dialogTitle: input
            ? 'XML-Exportordner auswählen'
            : 'PDF-Zielordner auswählen',
      );
      if (folder == null) return;
      final settingsFile = _settingsFile;
      if (settingsFile == null)
        throw StateError(
          'Einstellungen können nicht gespeichert werden. App bitte neu starten.',
        );
      await settingsFile.writeAsString(
        jsonEncode({
          'input': input ? folder : _input,
          'output': input ? _output : folder,
        }),
        flush: true,
      );
      if (mounted)
        setState(() {
          if (input) {
            _input = folder;
          } else {
            _output = folder;
          }
          _status =
              'Ordner gespeichert. Bereit zum Erstellen der Funktionsblätter.';
        });
    } catch (e) {
      if (mounted)
        setState(() => _status = 'Fehler beim Speichern der Ordner: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = 'Suche XML-Dateien …';
    });
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final result = await exportFolder(
        _input,
        _output,
        (sheet, modified) => createSheetPdf(sheet, modified, fontData),
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      if (mounted)
        setState(() {
          _status = result.found == 0
              ? 'Keine neuen XML-Dateien im Exportordner gefunden.'
              : '${result.pdfs.length} von ${result.found} PDF(s) erstellt.\nZielordner: $_output\n'
                    '${result.pdfs.map(p.basename).join('\n')}'
                    '${result.errors.isEmpty ? '\n\nVerarbeitete XML-Dateien wurden archiviert.' : '\n\nHinweise / Fehler:\n${result.errors.join('\n\n')}'}';
        });
    } catch (e) {
      if (mounted) setState(() => _status = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOutput() async {
    try {
      await Directory(_output).create(recursive: true);
      final process = await Process.run('explorer.exe', [_output]);
      // Explorer may return 1 even when it opens successfully.
      if (process.exitCode > 1)
        throw StateError('PDF-Ordner konnte nicht geöffnet werden.');
    } catch (e) {
      if (mounted)
        setState(() => _status = 'Fehler beim Öffnen des PDF-Ordners: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Funktionsblatt PDF Export')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('XML-Exportordner: $_input'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _pickFolder(true),
              icon: const Icon(Icons.folder_open),
              label: const Text('XML-Ordner ändern'),
            ),
          ),
          const SizedBox(height: 12),
          Text('PDF-Zielordner: $_output'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _pickFolder(false),
              icon: const Icon(Icons.folder_open),
              label: const Text('PDF-Ordner ändern'),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Funktionsblätter erstellen'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 80),
              textStyle: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ein PDF pro XML-Datei. Erfolgreich verarbeitete XML-Dateien werden in „Archiv“ verschoben. Vorhandene PDFs bleiben erhalten; weitere erhalten eine laufende Nummer.',
          ),
          const SizedBox(height: 24),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SelectableText(_status),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openOutput,
            icon: const Icon(Icons.folder_open),
            label: const Text('PDF-Ordner öffnen'),
          ),
        ],
      ),
    ),
  );
}
