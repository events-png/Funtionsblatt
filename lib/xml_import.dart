import 'package:xml/xml.dart';

class FunctionSheet {
  final List<Map<String, dynamic>> bookings;
  final String summary;
  final DateTime date;
  FunctionSheet(this.bookings, this.summary, this.date);

  String get filename {
    const weekdays = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}_${weekdays[date.weekday - 1]}.pdf';
  }
}

String _text(XmlElement element, String name) {
  for (final child in element.childElements) {
    if (child.name.local == name) return child.innerText.trim();
  }
  return '';
}

String _time(String raw) =>
    raw.length >= 12 ? '${raw.substring(8, 10)}:${raw.substring(10, 12)}' : '';

FunctionSheet parseFunctionSheet(String xml) {
  // ElementTree normalizes Windows line endings; preserve that behavior.
  final root = XmlDocument.parse(
    xml.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  ).rootElement;
  if (root.name.local != 'TempData') {
    throw const FormatException(
      'Keine Conqueror-Funktionsblatt-XML (TempData).',
    );
  }
  final reports = root.childElements
      .where((e) => e.name.local == 'RsrvReportData')
      .toList();
  final transactions = root.childElements
      .where((e) => e.name.local == 'TransactionsRows')
      .toList();
  final dates = reports
      .map((e) => _text(e, 'BookingDate'))
      .where((d) => d.length >= 8)
      .map((d) => d.substring(0, 8))
      .toSet();
  if (dates.length != 1) {
    throw const FormatException(
      'Die XML muss genau einen Reservierungstag enthalten.',
    );
  }
  final rawDate = dates.single;
  final date = DateTime(
    int.parse(rawDate.substring(0, 4)),
    int.parse(rawDate.substring(4, 6)),
    int.parse(rawDate.substring(6, 8)),
  );
  if ('${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}' !=
      rawDate) {
    throw const FormatException('Ungültiges Reservierungsdatum.');
  }
  const allowed = [
    'Zeitbowling_Resto',
    'Kids Birthday Party',
    'Kids Premium',
    'Family Bowl',
    'Family',
    'Party',
  ];
  final bookings = <Map<String, dynamic>>[];
  for (final report in reports) {
    final type = _text(report, 'BookingType');
    final description = _text(report, 'BookingTypeDesc');
    final lower = '$type $description'.toLowerCase();
    if (!allowed.any((a) => lower.contains(a.toLowerCase()))) continue;
    final notes = <String>{};
    final note = _text(
      report,
      'Note',
    ).replaceAll(RegExp('family bowl', caseSensitive: false), 'Family');
    if (note.isNotEmpty) notes.add(note);
    for (final transaction in transactions.where(
      (t) => _text(t, 'RsvId') == _text(report, 'RsvId'),
    )) {
      final text = _text(transaction, 'PriceKeyDescr');
      final lowerText = text.toLowerCase();
      if (lowerText.contains('tischreservierung vorher')) notes.add('vorher');
      if (lowerText.contains('tischreservierung nachher')) notes.add('nachher');
      if (lowerText.contains('fairy tale')) notes.add('Fairy Tale');
      if (lowerText.contains('monster')) notes.add('Monster');
      if (lowerText.contains('ocean') || lowerText.contains('ozean'))
        notes.add('Ocean');
      final cake = RegExp(
        r'(Geburtstags)?kuchen\s+\((.*?)\)',
        caseSensitive: false,
      ).firstMatch(text);
      if (cake != null) notes.add('Kuchen (${cake.group(2)})');
    }
    final hasTable = notes.contains('vorher') || notes.contains('nachher');
    // Preserve the existing converter's Family/Party filters.
    if ((lower.contains('family') || lower.contains('party')) && !hasTable)
      continue;
    final sortedNotes = notes.toList()..sort();
    bookings.add({
      'ID': _text(report, 'ReservationKey'),
      'Name': _text(
        report,
        'ResDescr',
      ).replaceFirst(RegExp(r'\s*\([^)]+\)$'), '').trim(),
      'BookingDate':
          '${rawDate.substring(6, 8)}/${rawDate.substring(4, 6)}/${rawDate.substring(0, 4)}',
      'BookingType': type,
      'BookingTypeDesc': description,
      'Bowlinguhrzeit': _time(_text(report, 'BowlingTime')),
      'Bowler': _text(report, 'NumberPeopleBowling'),
      'Resto': _time(_text(report, 'EatingTime')),
      'Pax': _text(report, 'NumberPeopleEating'),
      'Notiz': sortedNotes.join(', '),
    });
  }
  // Insertion sort preserves source order when restaurant times are equal.
  for (var i = 1; i < bookings.length; i++) {
    final item = bookings[i];
    final key = item['Resto'] == '' ? '99:99' : item['Resto'] as String;
    var j = i - 1;
    while (j >= 0) {
      final other = bookings[j]['Resto'] == ''
          ? '99:99'
          : bookings[j]['Resto'] as String;
      if (other.compareTo(key) <= 0) break;
      bookings[j + 1] = bookings[j];
      j--;
    }
    bookings[j + 1] = item;
  }
  var summary = '';
  for (final element in root.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'TotalPeopleEating',
  )) {
    final text = element.innerText.trim();
    if (text.length > summary.length) summary = text;
  }
  return FunctionSheet(bookings, summary, date);
}
