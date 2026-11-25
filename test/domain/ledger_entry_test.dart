import 'package:flutter_test/flutter_test.dart';
import 'package:darma/domain/ledger_entry.dart';

void main() {
  group('LedgerEntry', () {
    test('accepts a positive debit or credit entry', () {
      expect(const LedgerEntry(accountId: 1, debit: 100).isValid, isTrue);
      expect(const LedgerEntry(accountId: 2, credit: 100).isValid, isTrue);
    });

    test('rejects invalid account ids and empty entries', () {
      expect(const LedgerEntry(accountId: 0, debit: 100).isValid, isFalse);
      expect(const LedgerEntry(accountId: 1).isValid, isFalse);
    });

    test('rejects negative values and simultaneous debit and credit', () {
      expect(const LedgerEntry(accountId: 1, debit: -1).isValid, isFalse);
      expect(const LedgerEntry(accountId: 1, debit: 100, credit: 100).isValid,
          isFalse);
    });
  });

  group('LedgerDocument', () {
    test('accepts a balanced double-entry document', () {
      const document = LedgerDocument([
        LedgerEntry(accountId: 1, debit: 125000),
        LedgerEntry(accountId: 2, credit: 125000),
      ]);
      expect(document.isBalanced, isTrue);
    });

    test('rejects an unbalanced document', () {
      const document = LedgerDocument([
        LedgerEntry(accountId: 1, debit: 125000),
        LedgerEntry(accountId: 2, credit: 120000),
      ]);
      expect(document.isBalanced, isFalse);
    });

    test('rejects an entry with debit and credit together', () {
      const document = LedgerDocument([
        LedgerEntry(accountId: 1, debit: 100, credit: 100),
        LedgerEntry(accountId: 2, credit: 100),
      ]);
      expect(document.isBalanced, isFalse);
    });

    test('rejects empty, single-line, and zero-value documents', () {
      expect(const LedgerDocument([]).isBalanced, isFalse);
      expect(
        const LedgerDocument([LedgerEntry(accountId: 1, debit: 10)])
            .isBalanced,
        isFalse,
      );
      expect(
        const LedgerDocument([
          LedgerEntry(accountId: 1),
          LedgerEntry(accountId: 2),
        ]).isBalanced,
        isFalse,
      );
    });
  });
}
