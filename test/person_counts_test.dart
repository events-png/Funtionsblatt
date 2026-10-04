import 'package:flutter_test/flutter_test.dart';
import 'package:funktionsblatt/xml_import.dart';

String booking({
  String eating = '',
  String bowling = '5',
  String quantity = '1',
  String menu = '',
  String direction = 'nachher',
  String id = '1',
}) =>
    '''
<RsrvReportData><RsvId>$id</RsvId><BookingDate>20261004120000</BookingDate><BookingType>Kids Birthday Party</BookingType><NumberPeopleEating>$eating</NumberPeopleEating><NumberPeopleBowling>$bowling</NumberPeopleBowling><MenuChoices>$menu</MenuChoices></RsrvReportData>
<TransactionsRows><RsvId>$id</RsvId><PriceKeyDescr>Tischreservierung $direction</PriceKeyDescr><QuantitySold>$quantity</QuantitySold></TransactionsRows>''';
FunctionSheet sheet(String rows, {String summary = ''}) => parseFunctionSheet(
  '<TempData xmlns="http://tempuri.org/TempData.xsd">$rows<TotalPeopleEating>$summary</TotalPeopleEating></TempData>',
);

void main() {
  test('eating wins over table and bowling counts', () {
    final result = sheet(booking(eating: '16', bowling: '8', quantity: '8'));
    expect(result.bookings.single['Pax'], '16');
    expect(
      result.summary,
      'Tischreservierung nachher: 16 Personen / 1 Reservierung',
    );
  });
  test('table count greater than one wins when eating is missing or zero', () {
    for (final eating in ['', '0']) {
      final result = sheet(
        booking(eating: eating, bowling: '5', quantity: '8'),
      );
      expect(result.bookings.single['Pax'], '8');
    }
  });
  test('one table unit falls back to bowling', () {
    final result = sheet(booking(quantity: '1', bowling: '5'));
    expect(result.bookings.single['Pax'], '5');
    expect(result.summary, contains('5 Personen'));
  });
  test(
    'MenuChoices supplies the fallback without double counting transactions',
    () {
      final result = sheet(
        booking(quantity: '8', menu: '8 Tischreservierung nachher (Paid)'),
      );
      expect(result.bookings.single['Pax'], '8');
      final menuOnly = sheet(
        booking(quantity: '', menu: '7 Tischreservierung nachher (Paid)'),
      );
      expect(menuOnly.bookings.single['Pax'], '7');
    },
  );
  test(
    'missing person counts are explicit and not silently counted as one',
    () {
      final result = sheet(booking(eating: '', bowling: '0', quantity: '1'));
      expect(result.bookings.single['Pax'], 'offen');
      expect(result.bookings.single['Notiz'], contains('Personenzahl offen'));
      expect(result.summary, contains('mindestens 0 Personen'));
      expect(result.summary, contains('1 Personenzahl offen'));
    },
  );
  test(
    'before and after groups are separate; cake-only guests do not count',
    () {
      final rows =
          booking(eating: '5', direction: 'vorher') +
          booking(eating: '8', id: '2') +
          '''
<RsrvReportData><RsvId>3</RsvId><BookingDate>20261004120000</BookingDate><BookingType>Kids Birthday Party</BookingType><NumberPeopleEating>10</NumberPeopleEating></RsrvReportData>
<TransactionsRows><RsvId>3</RsvId><PriceKeyDescr>Kuchen (weiß)</PriceKeyDescr><QuantitySold>1</QuantitySold></TransactionsRows>''';
      final result = sheet(
        rows,
        summary: '99 Tischreservierung nachher\n1 Kuchen (weiß)',
      );
      expect(result.bookings.length, 3);
      expect(result.summary, contains('vorher: 5 Personen / 1 Reservierung'));
      expect(result.summary, contains('nachher: 8 Personen / 1 Reservierung'));
      expect(result.summary, contains('1 Kuchen (weiß)'));
      expect(result.summary, isNot(contains('99')));
    },
  );
  test('before plus after is the same group for the Pax column', () {
    final result = sheet(
      booking(quantity: '5') + '<TransactionsRows><RsvId>1</RsvId><PriceKeyDescr>Tischreservierung vorher</PriceKeyDescr><QuantitySold>5</QuantitySold></TransactionsRows>',
    );
    expect(result.bookings.single['Pax'], '5');
    expect(result.summary, contains('vorher: 5 Personen'));
    expect(result.summary, contains('nachher: 5 Personen'));
  });
}
