import 'package:flutter_test/flutter_test.dart';
import 'package:darma/domain/ledger_entry.dart';

void main() {
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
  });
}
