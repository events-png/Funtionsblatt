import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'xml_import.dart';

typedef PdfBuilder = Future<Uint8List> Function(FunctionSheet, DateTime);

Future<String> availablePath(String directory, String filename) async {
  var target = p.join(directory, filename);
  var counter = 2;
  while (await File(target).exists()) {
    target = p.join(
      directory,
      '${p.basenameWithoutExtension(filename)}_${counter++}${p.extension(filename)}',
    );
  }
  return target;
}

class BatchResult {
  final List<String> pdfs = [];
  final List<String> errors = [];
  int found = 0;
}

Future<BatchResult> exportFolder(
  String input,
  String output,
  PdfBuilder buildPdf, {
  void Function(String)? onProgress,
}) async {
  final result = BatchResult();
  final inputDir = Directory(input);
  if (!await inputDir.exists())
    throw FileSystemException('XML-Ordner nicht gefunden', input);
  await Directory(output).create(recursive: true);
  final files = await inputDir
      .list(followLinks: false)
      .where((e) => e is File && p.extension(e.path).toLowerCase() == '.xml')
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  result.found = files.length;
  for (final source in files) {
    final name = p.basename(source.path);
    onProgress?.call('Verarbeite $name …');
    File? temporary;
    try {
      final sheet = parseFunctionSheet(await source.readAsString());
      final bytes = await buildPdf(sheet, await source.lastModified());
      final target = await availablePath(output, sheet.filename);
      temporary = File('$target.part');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target);
      temporary = null;
      result.pdfs.add(target);
      // Archive only after the PDF has been saved successfully.
      try {
        final archive = p.join(input, 'Archiv');
        await Directory(archive).create(recursive: true);
        await source.rename(await availablePath(archive, name));
      } catch (e) {
        result.errors.add(
          '$name: PDF gespeichert, aber Archivierung fehlgeschlagen. XML bleibt im Exportordner; erneuter Start kann ein weiteres PDF erzeugen. $e',
        );
      }
    } catch (e) {
      result.errors.add('$name: $e');
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
  return result;
}
