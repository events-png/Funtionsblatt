import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:funktionsblatt/batch_export.dart';
import 'package:funktionsblatt/xml_import.dart';

String xml(
  String date,
  String name, {
  String type = 'Zeitbowling_Resto',
  String note = '',
}) =>
    '''
<TempData xmlns="http://tempuri.org/TempData.xsd">
<RsrvReportData><RsvId>1</RsvId><BookingDate>${date}140000</BookingDate>
<BookingType>$type</BookingType><ResDescr>$name</ResDescr><Note>$note</Note>
<NumberPeopleBowling>12</NumberPeopleBowling><EatingTime>${date}160000</EatingTime></RsrvReportData>
<TransactionsRows><RsvId>1</RsvId><PriceKeyDescr>Tischreservierung nachher</PriceKeyDescr></TransactionsRows>
<TotalPeopleEating>12 Tischreservierung nachher</TotalPeopleEating></TempData>''';

void main() {
  test('normalizes Windows line endings like the original converter', () {
    final sheet = parseFunctionSheet(
      xml('20261004', 'Test', note: 'Zeile 1\r\nZeile 2'),
    );
    expect(sheet.bookings.single['Notiz'], 'Zeile 1\nZeile 2, nachher');
  });
  test(
    'keeps days, bookings and summaries separate and archives only successes',
    () async {
      final root = await Directory.systemTemp.createTemp('sheet_test_');
      addTearDown(() => root.delete(recursive: true));
      final input = Directory('${root.path}/input')..createSync();
      final output = '${root.path}/pdf';
      await File('${input.path}/a.xml')
          .writeAsString(xml('20261004', 'Sonntag'));
      await File('${input.path}/b.XML')
          .writeAsString(xml('20261005', 'Montag'));
      await File('${input.path}/broken.xml').writeAsString('<broken');
      final sheets = <FunctionSheet>[];
      final result = await exportFolder(input.path, output, (sheet, _) async {
        sheets.add(sheet);
        return Uint8List.fromList([1, 2, 3]);
      });
      expect(result.found, 3);
      expect(result.pdfs.length, 2);
      expect(result.errors.length, 1);
      expect(sheets.map((s) => s.bookings.single['Name']), [
        'Sonntag',
        'Montag',
      ]);
      expect(result.pdfs.first, endsWith('2026-10-04_Sonntag.pdf'));
      expect(result.pdfs.last, endsWith('2026-10-05_Montag.pdf'));
      expect(await File('${input.path}/Archiv/a.xml').exists(), true);
      expect(await File('${input.path}/broken.xml').exists(), true);
      final repeat = await exportFolder(
        input.path,
        output,
        (_, __) async => Uint8List(0),
      );
      expect(repeat.pdfs, isEmpty);
      expect(repeat.found, 1);
    },
  );

  test('same-date PDFs and archived XMLs are never overwritten', () async {
    final root = await Directory.systemTemp.createTemp('sheet_collision_');
    addTearDown(() => root.delete(recursive: true));
    final input = Directory('${root.path}/input')..createSync();
    final archive = Directory('${input.path}/Archiv')..createSync();
    await File('${archive.path}/a.xml').writeAsString('original');
    for (final name in ['a', 'b']) {
      await File('${input.path}/$name.xml')
          .writeAsString(xml('20261004', name));
    }
    final result = await exportFolder(
      input.path,
      '${root.path}/pdf',
      (_, __) async => Uint8List.fromList([42]),
    );
    expect(result.pdfs.length, 2);
    expect(result.pdfs.last, endsWith('Sonntag_2.pdf'));
    expect(await File('${archive.path}/a.xml').readAsString(), 'original');
    expect(await File('${archive.path}/a_2.xml').exists(), true);
  });

  test('failed PDF generation leaves XML available for retry', () async {
    final root = await Directory.systemTemp.createTemp('sheet_failure_');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/a.xml');
    await source.writeAsString(xml('20261004', 'Test'));
    final result = await exportFolder(
      root.path,
      '${root.path}/pdf',
      (_, __) async => throw StateError('PDF failure'),
    );
    expect(result.pdfs, isEmpty);
    expect(result.errors.single, contains('PDF failure'));
    expect(await source.exists(), true);
  });

  test('rejects mixed days and retains legacy notes and filters', () {
    expect(
      () => parseFunctionSheet(
        xml('20261004', 'A').replaceFirst(
          '</TempData>',
          '<RsrvReportData><BookingDate>20261005120000</BookingDate></RsrvReportData></TempData>',
        ),
      ),
      throwsFormatException,
    );
    final sheet = parseFunctionSheet(
      xml(
        '20261004',
        'Name (Zusatz)',
        type: 'Family Bowl',
        note: 'Family Bowl &amp; mehr',
      ),
    );
    expect(sheet.bookings.single['Name'], 'Name');
    expect(sheet.bookings.single['Notiz'], 'Family & mehr, nachher');
    final noTable = xml(
      '20261004',
      'Test',
      type: 'Family Bowl',
    ).replaceAll('Tischreservierung nachher', 'Keine Tischbuchung');
    expect(parseFunctionSheet(noTable).bookings, isEmpty);
  });
}
