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

  group('TransactionJournal', () {
    test('posts income as debit to asset and credit to income', () {
      final entries = TransactionJournal.income(
        financialAccountId: 1,
        incomeAccountId: 2,
        amount: 250000,
      );
      expect(entries, [
        const LedgerEntry(accountId: 1, debit: 250000),
        const LedgerEntry(accountId: 2, credit: 250000),
      ]);
      expect(LedgerDocument(entries).isBalanced, isTrue);
    });

    test('posts expense and bank fee separately', () {
      final entries = TransactionJournal.expense(
        financialAccountId: 1,
        expenseAccountId: 2,
        feeAccountId: 3,
        amount: 100000,
        fee: 2500,
      );
      expect(entries, [
        const LedgerEntry(accountId: 2, debit: 100000),
        const LedgerEntry(accountId: 3, debit: 2500),
        const LedgerEntry(accountId: 1, credit: 102500),
      ]);
      expect(LedgerDocument(entries).isBalanced, isTrue);
    });

    test('posts expense without an extra fee line when fee is zero', () {
      final entries = TransactionJournal.expense(
        financialAccountId: 1,
        expenseAccountId: 2,
        feeAccountId: 0,
        amount: 100000,
      );
      expect(entries, [
        const LedgerEntry(accountId: 2, debit: 100000),
        const LedgerEntry(accountId: 1, credit: 100000),
      ]);
      expect(LedgerDocument(entries).isBalanced, isTrue);
    });

    test('posts transfer with fee as a separate expense', () {
      final entries = TransactionJournal.transfer(
        fromAccountId: 1,
        toAccountId: 2,
        feeAccountId: 3,
        amount: 50000,
        fee: 1000,
      );
      expect(entries, [
        const LedgerEntry(accountId: 1, credit: 51000),
        const LedgerEntry(accountId: 2, debit: 50000),
        const LedgerEntry(accountId: 3, debit: 1000),
      ]);
      expect(LedgerDocument(entries).isBalanced, isTrue);
    });

    test('posts transfer without a fee line when fee is zero', () {
      final entries = TransactionJournal.transfer(
        fromAccountId: 1,
        toAccountId: 2,
        feeAccountId: 0,
        amount: 50000,
      );
      expect(entries, [
        const LedgerEntry(accountId: 1, credit: 50000),
        const LedgerEntry(accountId: 2, debit: 50000),
      ]);
      expect(LedgerDocument(entries).isBalanced, isTrue);
    });

    test('rejects same source and destination accounts', () {
      expect(
        () => TransactionJournal.transfer(
          fromAccountId: 1,
          toAccountId: 1,
          amount: 100,
        ),
        throwsArgumentError,
      );
    });

    test('rejects zero amounts, negative fees and invalid account ids', () {
      expect(
        () => TransactionJournal.income(
          financialAccountId: 1,
          incomeAccountId: 2,
          amount: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TransactionJournal.expense(
          financialAccountId: 1,
          expenseAccountId: 2,
          feeAccountId: 3,
          amount: 100,
          fee: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => TransactionJournal.income(
          financialAccountId: 0,
          incomeAccountId: 2,
          amount: 100,
        ),
        throwsArgumentError,
      );
    });

    test('rejects fee account collisions and integer overflow', () {
      expect(
        () => TransactionJournal.transfer(
          fromAccountId: 1,
          toAccountId: 2,
          feeAccountId: 1,
          amount: 100,
          fee: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => TransactionJournal.expense(
          financialAccountId: 1,
          expenseAccountId: 2,
          feeAccountId: 3,
          amount: 9223372036854775807,
          fee: 1,
        ),
        throwsArgumentError,
      );
    });
  });

}
