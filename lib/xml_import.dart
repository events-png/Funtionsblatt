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

int _people(String raw) {
  final value = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (value == null ||
      !value.isFinite ||
      value <= 0 ||
      value != value.roundToDouble())
    return 0;
  return value.toInt();
}

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
    var beforeQuantity = 0;
    var afterQuantity = 0;
    for (final transaction in transactions.where(
      (t) => _text(t, 'RsvId') == _text(report, 'RsvId'),
    )) {
      final text = _text(transaction, 'PriceKeyDescr');
      final lowerText = text.toLowerCase();
      if (lowerText.contains('tischreservierung vorher')) {
        notes.add('vorher');
        beforeQuantity += _people(_text(transaction, 'QuantitySold'));
      }
      if (lowerText.contains('tischreservierung nachher')) {
        notes.add('nachher');
        afterQuantity += _people(_text(transaction, 'QuantitySold'));
      }
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
    // MenuChoices repeats the transaction quantities; do not add both sources.
    var menuBefore = 0;
    var menuAfter = 0;
    for (final match in RegExp(
      r'(\d+(?:[.,]\d+)?)\s+Tischreservierung\s+(vorher|nachher)\b',
      caseSensitive: false,
    ).allMatches(_text(report, 'MenuChoices'))) {
      final direction = match.group(2)!.toLowerCase();
      notes.add(direction);
      if (direction == 'vorher') {
        menuBefore += _people(match.group(1)!);
      } else {
        menuAfter += _people(match.group(1)!);
      }
    }
    if (menuBefore > beforeQuantity) beforeQuantity = menuBefore;
    if (menuAfter > afterQuantity) afterQuantity = menuAfter;
    final hasTable = notes.contains('vorher') || notes.contains('nachher');
    final hasCake = notes.any((note) => note.startsWith('Kuchen ('));
    // Cake orders also need a kitchen/service sheet without a table booking.
    if ((lower.contains('family') || lower.contains('party')) &&
        !hasTable &&
        !hasCake)
      continue;
    final eating = _people(_text(report, 'NumberPeopleEating'));
    final bowling = _people(_text(report, 'NumberPeopleBowling'));
    // A before AND after table booking is still the same group of people.
    final tableQuantity = beforeQuantity > afterQuantity
        ? beforeQuantity
        : afterQuantity;
    final pax = eating > 0
        ? eating
        : tableQuantity > 1
        ? tableQuantity
        : bowling;
    if (pax == 0) notes.add('Personenzahl offen');
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
      'Pax': pax > 0 ? pax.toString() : 'offen',
      'TableBefore': notes.contains('vorher'),
      'TableAfter': notes.contains('nachher'),
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
  // Conqueror's table totals count article units, not the resolved guest counts.
  final summaryLines = summary
      .split('\n')
      .where(
        (line) =>
            line.trim().isNotEmpty &&
            !RegExp(
              r'tischreservierung\s+(vorher|nachher)',
              caseSensitive: false,
            ).hasMatch(line),
      )
      .toList();
  for (final direction in ['vorher', 'nachher']) {
    final key = direction == 'vorher' ? 'TableBefore' : 'TableAfter';
    final tables = bookings.where((booking) => booking[key] == true).toList();
    if (tables.isEmpty) continue;
    final total = tables.fold<int>(
      0,
      (sum, booking) => sum + _people(booking['Pax'] as String),
    );
    final unknown = tables.where((booking) => booking['Pax'] == 'offen').length;
    final countLabel = tables.length == 1 ? 'Reservierung' : 'Reservierungen';
    final openLabel = unknown > 0 ? ' ($unknown Personenzahl offen)' : '';
    summaryLines.add(
      'Tischreservierung $direction: ${unknown > 0 ? 'mindestens ' : ''}$total Personen / ${tables.length} $countLabel$openLabel',
    );
  }
  return FunctionSheet(bookings, summaryLines.join('\n'), date);
}
