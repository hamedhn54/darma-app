import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:darma/data/darma_database.dart';

void main() {
  late DarmaDatabase database;
  late Database rawDatabase;
  late int bankOneId;
  late int bankTwoId;
  late int incomeId;
  late int expenseId;
  late int feeAccountId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<int> findAccountId(String name, String type) async {
    final rows = await rawDatabase.query(
      'accounts',
      columns: ['id'],
      where: 'name = ? AND type = ?',
      whereArgs: [name, type],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Test account not found: $name');
    return rows.first['id'] as int;
  }

  Future<int> balanceOf(int accountId) async {
    final summaries = await database.getAccountSummaries();
    final row = summaries.singleWhere((item) => item['id'] == accountId);
    return (row['balance'] as num).toInt();
  }

  setUp(() async {
    database = DarmaDatabase.forTesting(databasePath: inMemoryDatabasePath);
    rawDatabase = await database.database;

    final bankGroupId = await findAccountId('حساب بانکی', 'asset');
    final incomeGroupId = await findAccountId('حقوق و دستمزد', 'income');
    final expenseGroupId = await findAccountId('خوراک و مواد غذایی', 'expense');

    bankOneId = await database.createAccount(
      name: 'بانک آزمایشی یک',
      type: 'asset',
      parentId: bankGroupId,
      accountKind: 'bank',
      bankName: 'بانک آزمایش',
      openingBalance: 1000000,
    );
    bankTwoId = await database.createAccount(
      name: 'بانک آزمایشی دو',
      type: 'asset',
      parentId: bankGroupId,
      accountKind: 'bank',
      bankName: 'بانک آزمایش',
      openingBalance: 250000,
    );
    incomeId = await database.createAccount(
      name: 'حقوق آزمایشی',
      type: 'income',
      parentId: incomeGroupId,
    );
    expenseId = await database.createAccount(
      name: 'هزینه آزمایشی',
      type: 'expense',
      parentId: expenseGroupId,
    );
    feeAccountId = await findAccountId('کارمزد بانکی', 'expense');
  });

  group('DarmaDatabase SQLite integration', () {
    test('records income, expense fee and transfer with correct balances', () async {
      await database.addSimpleTransaction(
        title: 'حقوق ماهانه',
        amount: 100000,
        kind: 'income',
        categoryAccountId: incomeId,
        financialAccountId: bankOneId,
      );
      await database.addSimpleTransaction(
        title: 'خرید روزانه',
        amount: 20000,
        kind: 'expense',
        categoryAccountId: expenseId,
        financialAccountId: bankOneId,
        fee: 1000,
      );
      await database.addTransfer(
        title: 'انتقال بین حساب‌ها',
        amount: 300000,
        fromAccountId: bankOneId,
        toAccountId: bankTwoId,
        fee: 500,
      );

      expect(await balanceOf(bankOneId), 778500);
      expect(await balanceOf(bankTwoId), 550000);
      expect(await balanceOf(incomeId), 100000);
      expect(await balanceOf(expenseId), 20000);
      expect(await balanceOf(feeAccountId), 1500);
      expect((await database.getTransactions()).length, 3);

      final documents = await rawDatabase.rawQuery('''
        SELECT transaction_id, SUM(debit) AS debit_total,
          SUM(credit) AS credit_total
        FROM journal_entries
        GROUP BY transaction_id
      ''');
      expect(documents.length, 3);
      for (final document in documents) {
        expect(document['debit_total'], document['credit_total']);
      }
    });

    test('updates income, expense and transfer without leaving stale entries', () async {
      await database.addSimpleTransaction(
        title: 'حقوق اولیه',
        amount: 100000,
        kind: 'income',
        categoryAccountId: incomeId,
        financialAccountId: bankOneId,
      );
      final incomeTransactionId =
          (await database.getTransactions()).first['id'] as int;
      await database.updateSimpleTransaction(
        transactionId: incomeTransactionId,
        title: 'حقوق اصلاح‌شده',
        amount: 150000,
        kind: 'income',
        categoryAccountId: incomeId,
        financialAccountId: bankOneId,
      );

      await database.addSimpleTransaction(
        title: 'هزینه اولیه',
        amount: 20000,
        kind: 'expense',
        categoryAccountId: expenseId,
        financialAccountId: bankOneId,
        fee: 1000,
      );
      final expenseTransactionId =
          (await database.getTransactions()).first['id'] as int;
      await database.updateSimpleTransaction(
        transactionId: expenseTransactionId,
        title: 'هزینه اصلاح‌شده',
        amount: 30000,
        kind: 'expense',
        categoryAccountId: expenseId,
        financialAccountId: bankOneId,
        fee: 2000,
      );

      await database.addTransfer(
        title: 'انتقال اولیه',
        amount: 100000,
        fromAccountId: bankOneId,
        toAccountId: bankTwoId,
        fee: 500,
      );
      final transferTransactionId =
          (await database.getTransactions()).first['id'] as int;
      await database.updateTransfer(
        transactionId: transferTransactionId,
        title: 'انتقال اصلاح‌شده',
        amount: 80000,
        fromAccountId: bankOneId,
        toAccountId: bankTwoId,
        fee: 250,
      );

      expect(await balanceOf(bankOneId), 1037750);
      expect(await balanceOf(bankTwoId), 330000);
      expect(await balanceOf(incomeId), 150000);
      expect(await balanceOf(expenseId), 30000);
      expect(await balanceOf(feeAccountId), 2250);

      final entryCounts = await rawDatabase.rawQuery('''
        SELECT transaction_id, COUNT(*) AS row_count
        FROM journal_entries
        GROUP BY transaction_id
      ''');
      expect(entryCounts.length, 3);
      expect(entryCounts.map((row) => row['row_count']).toSet(), {2, 3});
    });

    test('deletes a transaction and all its journal entries', () async {
      await database.addSimpleTransaction(
        title: 'دریافتی قابل حذف',
        amount: 25000,
        kind: 'income',
        categoryAccountId: incomeId,
        financialAccountId: bankOneId,
      );
      final transactionId =
          (await database.getTransactions()).single['id'] as int;

      await database.deleteTransaction(transactionId);

      expect(await database.getTransactions(), isEmpty);
      expect(
        await rawDatabase.rawQuery(
          'SELECT id FROM journal_entries WHERE transaction_id = ?',
          [transactionId],
        ),
        isEmpty,
      );
      expect(await balanceOf(bankOneId), 1000000);
      expect(await balanceOf(incomeId), 0);
    });

    test('rolls back an update when rebuilding journal entries fails', () async {
      await database.addSimpleTransaction(
        title: 'هزینه ثبت‌شده',
        amount: 10000,
        kind: 'expense',
        categoryAccountId: expenseId,
        financialAccountId: bankOneId,
      );
      final transactionId =
          (await database.getTransactions()).single['id'] as int;

      await rawDatabase.delete(
        'accounts',
        where: 'id = ?',
        whereArgs: [feeAccountId],
      );

      await expectLater(
        database.updateSimpleTransaction(
          transactionId: transactionId,
          title: 'نباید ذخیره شود',
          amount: 50000,
          kind: 'expense',
          categoryAccountId: expenseId,
          financialAccountId: bankOneId,
          fee: 1000,
        ),
        throwsA(isA<StateError>()),
      );

      final transaction = (await database.getTransactions()).single;
      expect(transaction['title'], 'هزینه ثبت‌شده');
      expect(transaction['amount'], 10000);
      expect(await balanceOf(bankOneId), 990000);
      expect(
        await rawDatabase.rawQuery(
          'SELECT id FROM journal_entries WHERE transaction_id = ?',
          [transactionId],
        ),
        hasLength(2),
      );
    });

    test('rolls back a new transaction if journal creation fails', () async {
      await rawDatabase.delete(
        'accounts',
        where: 'id = ?',
        whereArgs: [feeAccountId],
      );

      await expectLater(
        database.addSimpleTransaction(
          title: 'تراکنش ناموفق',
          amount: 10000,
          kind: 'expense',
          categoryAccountId: expenseId,
          financialAccountId: bankOneId,
          fee: 500,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await database.getTransactions(), isEmpty);
      expect(
        await rawDatabase.rawQuery('SELECT id FROM journal_entries'),
        isEmpty,
      );
      expect(await balanceOf(bankOneId), 1000000);
    });
  });
}
