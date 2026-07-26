import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/services/ocr/receipt_scanner.dart';

void main() {
  group('ReceiptParser', () {
    test('prefers the amount on the line labelled total', () {
      const raw = '''
CORNER CAFE
12 High Street
2026-07-20

Flat white        3.40
Croissant         2.80
Subtotal          6.20
TOTAL             6.20
Card payment
''';

      final receipt = ReceiptParser.parse(raw);

      expect(receipt.merchant, 'CORNER CAFE');
      expect(receipt.totalMinor, 620);
      expect(receipt.date, DateTime(2026, 7, 20));
      expect(receipt.isUsable, isTrue);
    });

    test('falls back to the largest amount when nothing says total', () {
      const raw = '''
MARKET
Apples 2.50
Bread 3.10
Cheese 7.95
''';

      expect(ReceiptParser.parse(raw).totalMinor, 795);
    });

    test('reads comma decimal separators', () {
      const raw = 'BOULANGERIE\nTOTAL 12,40';
      expect(ReceiptParser.parse(raw).totalMinor, 1240);
    });

    test('parses day-first slash dates', () {
      const raw = 'SHOP\n20/07/2026\nTOTAL 5.00';
      expect(ReceiptParser.parse(raw).date, DateTime(2026, 7, 20));
    });

    test('rejects an impossible month rather than guessing', () {
      const raw = 'SHOP\n20/13/2026\nTOTAL 5.00';
      expect(ReceiptParser.parse(raw).date, isNull);
    });

    test('reports low confidence when no amount was found', () {
      final receipt = ReceiptParser.parse('SOME SHOP\nthank you');

      expect(receipt.totalMinor, isNull);
      expect(receipt.isUsable, isFalse);
      expect(receipt.confidence, lessThan(0.5));
    });
  });

  test('the stub scanner reports itself unavailable instead of failing oddly',
      () async {
    const scanner = StubReceiptScanner();
    expect(scanner.isAvailable, isFalse);
  });
}
