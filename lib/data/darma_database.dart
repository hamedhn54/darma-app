import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DarmaDatabase {
  DarmaDatabase._();
  static final DarmaDatabase instance = DarmaDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'darma.db'),
      version: 5,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        final now = DateTime.now().toIso8601String();
        final roots = {
          'دارایی‌ها': 'asset',
          'بدهی‌ها': 'liability',
          'درآمدها': 'income',
          'هزینه‌ها': 'expense',
        };
        for (final e in roots.entries) {
          await db.insert('accounts', {
            'name': e.key,
            'type': e.value,
            'is_system': 1,
            'created_at': now,
          });
        }
        await _seedDefaultAccounts(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE journal_transactions ADD COLUMN fee INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await _seedDefaultAccounts(db);
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE accounts ADD COLUMN account_kind TEXT');
          await db.execute('ALTER TABLE accounts ADD COLUMN bank_name TEXT');
          await db.execute('ALTER TABLE accounts ADD COLUMN card_number TEXT');
          await db.execute('ALTER TABLE accounts ADD COLUMN opening_balance INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
    return _db!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('asset','liability','income','expense')),
        parent_id INTEGER,
        is_system INTEGER NOT NULL DEFAULT 0,
        account_kind TEXT,
        bank_name TEXT,
        card_number TEXT,
        opening_balance INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(parent_id) REFERENCES accounts(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        fee INTEGER NOT NULL DEFAULT 0 CHECK(fee >= 0),
        kind TEXT NOT NULL CHECK(kind IN ('income','expense','transfer')),
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        debit INTEGER NOT NULL DEFAULT 0,
        credit INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(transaction_id) REFERENCES journal_transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(account_id) REFERENCES accounts(id),
        CHECK(debit >= 0 AND credit >= 0),
        CHECK(NOT (debit > 0 AND credit > 0))
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_entries_account ON journal_entries(account_id)');
    await db.execute(
        'CREATE INDEX idx_entries_transaction ON journal_entries(transaction_id)');
  }

  Future<void> _seedDefaultAccounts(DatabaseExecutor db) async {
    final defaults = <String, List<String>>{
      'asset': [
        'کیف پول نقدی',
        'حساب بانکی',
        'کیف پول الکترونیکی',
        'پس‌انداز',
        'سرمایه‌گذاری',
        'طلب از اشخاص',
      ],
      'liability': [
        'وام دریافتی',
        'بدهی به اشخاص',
        'خرید اعتباری',
        'اقساط پرداختنی',
        'بدهی کارت و تسهیلات',
      ],
      'income': [
        'حقوق و دستمزد',
        'درآمد شغلی',
        'درآمد کسب‌وکار',
        'درآمد سرمایه‌گذاری',
        'سود سپرده بانکی',
        'هدایا و دریافتی‌های متفرقه',
      ],
      'expense': [
        'خوراک و مواد غذایی',
        'مسکن و اجاره',
        'قبوض و خدمات',
        'حمل‌ونقل و خودرو',
        'درمان و بهداشت',
        'پوشاک و لوازم شخصی',
        'آموزش و توسعه فردی',
        'تفریح و سفر',
        'خرید لوازم خانه',
        'هزینه‌های خانواده',
        'کارمزد بانکی',
        'مالیات و عوارض',
        'سایر هزینه‌ها',
      ],
    };
    final now = DateTime.now().toIso8601String();
    for (final group in defaults.entries) {
      final rootId = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT id FROM accounts WHERE type = ? AND parent_id IS NULL LIMIT 1',
        [group.key],
      ));
      if (rootId == null) continue;
      for (final name in group.value) {
        final existing = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM accounts WHERE type = ? AND name = ?',
          [group.key, name],
        ));
        if ((existing ?? 0) > 0) continue;
        await db.insert('accounts', {
          'name': name,
          'type': group.key,
          'parent_id': rootId,
          'is_system': name == 'کیف پول نقدی' ? 1 : 0,
          'created_at': now,
        });
      }
    }
  }

  Future<List<Map<String, Object?>>> getTransactionAccounts(String type) async {
    final db = await database;
    return db.rawQuery('''
      SELECT a.id, a.name, a.parent_id, a.account_kind, a.bank_name,
        a.card_number, a.opening_balance,
        COALESCE(a.opening_balance, 0) + COALESCE((
          SELECT SUM(e.debit - e.credit) FROM journal_entries e
          WHERE e.account_id = a.id
        ), 0) AS balance,
        (SELECT COUNT(*) FROM accounts child WHERE child.parent_id = a.id) AS child_count
      FROM accounts a
      WHERE a.type = ? AND a.parent_id IS NOT NULL
      ORDER BY a.parent_id, a.id
    ''', [type]);
  }

  Future<int> _bankFeeAccountId(DatabaseExecutor txn) async {
    final id = Sqflite.firstIntValue(await txn.rawQuery(
      "SELECT id FROM accounts WHERE name = 'کارمزد بانکی' AND type = 'expense' LIMIT 1",
    ));
    if (id == null) throw StateError('حساب کارمزد بانکی یافت نشد');
    return id;
  }

  Future<void> _checkDuplicate(
    DatabaseExecutor txn, {
    required String title,
    required int amount,
    required int fee,
    required String kind,
    int? categoryAccountId,
    int? fromAccountId,
    int? toAccountId,
  }) async {
    final cutoff =
        DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
    if (kind != 'transfer' && categoryAccountId != null) {
      final rows = await txn.rawQuery('''
        SELECT COUNT(*) FROM journal_transactions t
        WHERE t.title = ? AND t.amount = ? AND t.fee = ? AND t.kind = ? AND t.created_at >= ?
          AND EXISTS (SELECT 1 FROM journal_entries e WHERE e.transaction_id = t.id AND e.account_id = ?)
      ''', [title.trim(), amount, fee, kind, cutoff, categoryAccountId]);
      if ((Sqflite.firstIntValue(rows) ?? 0) > 0) {
        throw StateError('تراکنش مشابه در یک دقیقه اخیر ثبت شده است');
      }
    } else if (kind == 'transfer' &&
        fromAccountId != null &&
        toAccountId != null) {
      final rows = await txn.rawQuery('''
        SELECT COUNT(*) FROM journal_transactions t
        WHERE t.title = ? AND t.amount = ? AND t.fee = ? AND t.kind = 'transfer' AND t.created_at >= ?
          AND EXISTS (SELECT 1 FROM journal_entries e WHERE e.transaction_id = t.id AND e.account_id = ? AND e.credit > 0)
          AND EXISTS (SELECT 1 FROM journal_entries e WHERE e.transaction_id = t.id AND e.account_id = ? AND e.debit > 0)
      ''', [title.trim(), amount, fee, cutoff, fromAccountId, toAccountId]);
      if ((Sqflite.firstIntValue(rows) ?? 0) > 0) {
        throw StateError('انتقال مشابه در یک دقیقه اخیر ثبت شده است');
      }
    }
  }

  Future<void> _assertBalanced(DatabaseExecutor txn, int transactionId) async {
    final totals = await txn.rawQuery(
      'SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_entries WHERE transaction_id = ?',
      [transactionId],
    );
    if ((totals.first['d'] as num) != (totals.first['c'] as num)) {
      throw StateError('سند حسابداری تراز نیست');
    }
  }

  Future<void> _validateAssetAccounts(
      DatabaseExecutor txn, List<int> ids) async {
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await txn.rawQuery('''
      SELECT a.id FROM accounts a
      WHERE a.id IN ($placeholders)
        AND a.type = 'asset'
        AND a.parent_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM accounts c WHERE c.parent_id = a.id)
    ''', ids);
    if (rows.length != ids.length)
      throw StateError('حساب مبدأ یا مقصد معتبر نیست');
  }

  Future<void> addSimpleTransaction({
    required String title,
    required int amount,
    required String kind,
    required int categoryAccountId,
    int? financialAccountId,
    int fee = 0,
  }) async {
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (fee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد');
    if (kind != 'income' && kind != 'expense')
      throw ArgumentError('نوع تراکنش نامعتبر است');
    if (kind == 'income' && fee > 0)
      throw ArgumentError('کارمزد فقط برای پرداخت و انتقال مجاز است');

    final db = await database;
    await db.transaction((txn) async {
      await _checkDuplicate(txn,
          title: title,
          amount: amount,
          fee: fee,
          kind: kind,
          categoryAccountId: categoryAccountId);

      final selected = await txn.query(
        'accounts',
        where: 'id = ? AND type = ? AND parent_id IS NOT NULL',
        whereArgs: [categoryAccountId, kind],
        limit: 1,
      );
      if (selected.isEmpty) throw StateError('حساب انتخاب‌شده معتبر نیست');
      final children = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE parent_id = ?',
        [categoryAccountId],
      ));
      if ((children ?? 0) > 0)
        throw StateError('برای ثبت تراکنش، تفصیلی این معین را انتخاب کنید');

      final defaultCash = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT id FROM accounts WHERE name = 'کیف پول نقدی' AND type = 'asset' LIMIT 1",
      ));
      final financialId = financialAccountId ?? defaultCash;
      if (financialId == null) throw StateError('حساب مالی پیش‌فرض پیدا نشد');
      await _validateAssetAccounts(txn, [financialId]);

      final id = await txn.insert('journal_transactions', {
        'title': title.trim(),
        'amount': amount,
        'fee': fee,
        'kind': kind,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (kind == 'income') {
        await txn.insert('journal_entries', {
          'transaction_id': id,
          'account_id': financialId,
          'debit': amount,
          'credit': 0
        });
        await txn.insert('journal_entries', {
          'transaction_id': id,
          'account_id': categoryAccountId,
          'debit': 0,
          'credit': amount
        });
      } else {
        await txn.insert('journal_entries', {
          'transaction_id': id,
          'account_id': categoryAccountId,
          'debit': amount,
          'credit': 0
        });
        if (fee > 0) {
          final bankFee = await _bankFeeAccountId(txn);
          await txn.insert('journal_entries', {
            'transaction_id': id,
            'account_id': bankFee,
            'debit': fee,
            'credit': 0
          });
        }
        await txn.insert('journal_entries', {
          'transaction_id': id,
          'account_id': financialId,
          'debit': 0,
          'credit': amount + fee
        });
      }

      await _assertBalanced(txn, id);
    });
  }

  Future<void> updateSimpleTransaction({
    required int transactionId,
    required String title,
    required int amount,
    required String kind,
    required int categoryAccountId,
    int? financialAccountId,
    int fee = 0,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('شرح تراکنش الزامی است');
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (fee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد');
    if (kind != 'income' && kind != 'expense')
      throw ArgumentError('نوع تراکنش نامعتبر است');
    if (kind == 'income' && fee > 0)
      throw ArgumentError('کارمزد فقط برای پرداخت و انتقال مجاز است');

    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('journal_transactions',
          where: 'id = ?', whereArgs: [transactionId], limit: 1);
      if (rows.isEmpty) throw StateError('تراکنش پیدا نشد');
      if (rows.first['kind'] == 'transfer')
        throw StateError('برای ویرایش انتقال از updateTransfer استفاده کنید');

      final categoryRows = await txn.query(
        'accounts',
        where: 'id = ? AND type = ? AND parent_id IS NOT NULL',
        whereArgs: [categoryAccountId, kind],
        limit: 1,
      );
      if (categoryRows.isEmpty) throw StateError('حساب انتخاب‌شده معتبر نیست');
      final children = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE parent_id = ?',
        [categoryAccountId],
      ));
      if ((children ?? 0) > 0)
        throw StateError('برای ثبت تراکنش، تفصیلی را انتخاب کنید');

      final defaultCash = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT id FROM accounts WHERE name = 'کیف پول نقدی' AND type = 'asset' LIMIT 1",
      ));
      final financialId = financialAccountId ?? defaultCash;
      if (financialId == null) throw StateError('حساب مالی پیش‌فرض پیدا نشد');
      await _validateAssetAccounts(txn, [financialId]);

      await txn.update(
        'journal_transactions',
        {'title': title.trim(), 'amount': amount, 'fee': fee, 'kind': kind},
        where: 'id = ?',
        whereArgs: [transactionId],
      );

      await txn.delete('journal_entries',
          where: 'transaction_id = ?', whereArgs: [transactionId]);

      if (kind == 'income') {
        await txn.insert('journal_entries', {
          'transaction_id': transactionId,
          'account_id': financialId,
          'debit': amount,
          'credit': 0
        });
        await txn.insert('journal_entries', {
          'transaction_id': transactionId,
          'account_id': categoryAccountId,
          'debit': 0,
          'credit': amount
        });
      } else {
        await txn.insert('journal_entries', {
          'transaction_id': transactionId,
          'account_id': categoryAccountId,
          'debit': amount,
          'credit': 0
        });
        if (fee > 0) {
          final bankFee = await _bankFeeAccountId(txn);
          await txn.insert('journal_entries', {
            'transaction_id': transactionId,
            'account_id': bankFee,
            'debit': fee,
            'credit': 0
          });
        }
        await txn.insert('journal_entries', {
          'transaction_id': transactionId,
          'account_id': financialId,
          'debit': 0,
          'credit': amount + fee
        });
      }

      await _assertBalanced(txn, transactionId);
    });
  }

  Future<void> addTransfer({
    required String title,
    required int amount,
    required int fromAccountId,
    required int toAccountId,
    int fee = 0,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('شرح انتقال الزامی است');
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (fee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد');
    if (fromAccountId == toAccountId)
      throw ArgumentError('حساب مبدأ و مقصد باید متفاوت باشند');

    final db = await database;
    await db.transaction((txn) async {
      await _validateAssetAccounts(txn, [fromAccountId, toAccountId]);
      await _checkDuplicate(txn,
          title: title,
          amount: amount,
          fee: fee,
          kind: 'transfer',
          fromAccountId: fromAccountId,
          toAccountId: toAccountId);

      final id = await txn.insert('journal_transactions', {
        'title': title.trim(),
        'amount': amount,
        'fee': fee,
        'kind': 'transfer',
        'created_at': DateTime.now().toIso8601String(),
      });

      await txn.insert('journal_entries', {
        'transaction_id': id,
        'account_id': fromAccountId,
        'debit': 0,
        'credit': amount + fee
      });
      await txn.insert('journal_entries', {
        'transaction_id': id,
        'account_id': toAccountId,
        'debit': amount,
        'credit': 0
      });
      if (fee > 0) {
        final bankFee = await _bankFeeAccountId(txn);
        await txn.insert('journal_entries', {
          'transaction_id': id,
          'account_id': bankFee,
          'debit': fee,
          'credit': 0
        });
      }

      await _assertBalanced(txn, id);
    });
  }

  Future<void> updateTransfer({
    required int transactionId,
    required String title,
    required int amount,
    required int fromAccountId,
    required int toAccountId,
    int fee = 0,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('شرح انتقال الزامی است');
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (fee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد');
    if (fromAccountId == toAccountId)
      throw ArgumentError('حساب مبدأ و مقصد باید متفاوت باشند');

    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('journal_transactions',
          where: 'id = ?', whereArgs: [transactionId], limit: 1);
      if (rows.isEmpty) throw StateError('انتقال پیدا نشد');
      if (rows.first['kind'] != 'transfer')
        throw StateError('این تراکنش انتقال نیست');

      await _validateAssetAccounts(txn, [fromAccountId, toAccountId]);

      await txn.update(
        'journal_transactions',
        {'title': title.trim(), 'amount': amount, 'fee': fee},
        where: 'id = ?',
        whereArgs: [transactionId],
      );

      await txn.delete('journal_entries',
          where: 'transaction_id = ?', whereArgs: [transactionId]);

      await txn.insert('journal_entries', {
        'transaction_id': transactionId,
        'account_id': fromAccountId,
        'debit': 0,
        'credit': amount + fee
      });
      await txn.insert('journal_entries', {
        'transaction_id': transactionId,
        'account_id': toAccountId,
        'debit': amount,
        'credit': 0
      });
      if (fee > 0) {
        final bankFee = await _bankFeeAccountId(txn);
        await txn.insert('journal_entries', {
          'transaction_id': transactionId,
          'account_id': bankFee,
          'debit': fee,
          'credit': 0
        });
      }

      await _assertBalanced(txn, transactionId);
    });
  }

  Future<List<Map<String, Object?>>> getTransactions() async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.id, t.title, t.amount, t.fee, t.kind, t.note, t.created_at,
        (SELECT e.account_id FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND a.type = t.kind LIMIT 1) AS category_account_id,
        (SELECT a.name FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND a.type = t.kind LIMIT 1) AS category_name,
        (SELECT CASE WHEN p.parent_id IS NULL THEN a.name ELSE p.name END FROM journal_entries e JOIN accounts a ON a.id = e.account_id LEFT JOIN accounts p ON p.id = a.parent_id WHERE e.transaction_id = t.id AND a.type = t.kind LIMIT 1) AS parent_name,
        (SELECT e.account_id FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND t.kind = 'transfer' AND a.type = 'asset' AND e.credit > 0 LIMIT 1) AS from_account_id,
        (SELECT a.name FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND t.kind = 'transfer' AND a.type = 'asset' AND e.credit > 0 LIMIT 1) AS from_account_name,
        (SELECT e.account_id FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND t.kind = 'transfer' AND a.type = 'asset' AND e.debit > 0 LIMIT 1) AS to_account_id,
        (SELECT a.name FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND t.kind = 'transfer' AND a.type = 'asset' AND e.debit > 0 LIMIT 1) AS to_account_name,
        (SELECT e.account_id FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND a.type = 'asset' AND ((t.kind = 'income' AND e.debit > 0) OR (t.kind = 'expense' AND e.credit > 0)) LIMIT 1) AS financial_account_id,
        (SELECT a.name FROM journal_entries e JOIN accounts a ON a.id = e.account_id WHERE e.transaction_id = t.id AND a.type = 'asset' AND ((t.kind = 'income' AND e.debit > 0) OR (t.kind = 'expense' AND e.credit > 0)) LIMIT 1) AS financial_account_name
      FROM journal_transactions t
      ORDER BY t.id DESC
    ''');
  }

  Future<void> deleteTransaction(int transactionId) async {
    final db = await database;
    await db.transaction((txn) async {
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM journal_transactions WHERE id = ?',
        [transactionId],
      ));
      if ((count ?? 0) == 0) throw StateError('تراکنش پیدا نشد');
      await txn.delete('journal_entries',
          where: 'transaction_id = ?', whereArgs: [transactionId]);
      await txn.delete('journal_transactions',
          where: 'id = ?', whereArgs: [transactionId]);
    });
  }

  Future<List<Map<String, Object?>>> getAccountSummaries() async {
    final db = await database;
    return db.rawQuery('''
      SELECT a.id, a.name, a.type, a.parent_id, a.is_system,
        a.account_kind, a.bank_name, a.card_number, a.opening_balance,
        (SELECT root.id FROM accounts root WHERE root.type = a.type AND root.parent_id IS NULL LIMIT 1) AS root_id,
        CASE WHEN a.type IN ('asset','expense')
          THEN COALESCE(a.opening_balance, 0) + COALESCE(SUM(e.debit - e.credit), 0)
          ELSE COALESCE(SUM(e.credit - e.debit), 0)
        END AS balance,
        COUNT(e.id) AS entry_count
      FROM accounts a
      LEFT JOIN journal_entries e ON e.account_id = a.id
      WHERE a.parent_id IS NOT NULL
      GROUP BY a.id
      ORDER BY a.type, a.id
    ''');
  }

  Future<int> createAccount({
    required String name,
    required String type,
    int? parentId,
    String? accountKind,
    String? bankName,
    String? cardNumber,
    int openingBalance = 0,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('نام حساب الزامی است');
    if (openingBalance < 0) throw ArgumentError('موجودی اولیه نمی‌تواند منفی باشد');
    if (accountKind != null &&
        !const ['bank', 'cash', 'wallet', 'other'].contains(accountKind)) {
      throw ArgumentError('نوع حساب مالی نامعتبر است');
    }
    if (type != 'asset' &&
        (accountKind != null || openingBalance != 0)) {
      throw ArgumentError('اطلاعات حساب مالی فقط برای دارایی‌ها مجاز است');
    }
    if (!const ['asset', 'liability', 'income', 'expense'].contains(type)) {
      throw ArgumentError('نوع حساب نامعتبر است');
    }
    final db = await database;
    return db.transaction((txn) async {
      int targetParent;
      if (parentId == null) {
        final rootId = Sqflite.firstIntValue(await txn.rawQuery(
          'SELECT id FROM accounts WHERE type = ? AND parent_id IS NULL LIMIT 1',
          [type],
        ));
        if (rootId == null) throw StateError('سرفصل اصلی پیدا نشد');
        targetParent = rootId;
      } else {
        final parents = await txn.query('accounts',
            where: 'id = ?', whereArgs: [parentId], limit: 1);
        if (parents.isEmpty || parents.first['type'] != type) {
          throw StateError('حساب معین معتبر نیست');
        }
        if (parents.first['parent_id'] == null) {
          throw StateError('امکان ایجاد تفصیلی زیر سرفصل اصلی وجود ندارد');
        }
        if (type == 'asset') {
          final used = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM journal_entries WHERE account_id = ?',
            [parentId],
          ));
          if ((used ?? 0) > 0) {
            throw StateError('این حساب گردش مالی دارد و نمی‌توان آن را به حساب مادر تبدیل کرد');
          }
        }
        targetParent = parentId;
      }
      final duplicate = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE name = ? AND type = ? AND parent_id = ?',
        [cleanName, type, targetParent],
      ));
      if ((duplicate ?? 0) > 0)
        throw StateError('حسابی با این نام در این گروه وجود دارد');
      return txn.insert('accounts', {
        'name': cleanName,
        'type': type,
        'parent_id': targetParent,
        'is_system': 0,
        'account_kind': accountKind,
        'bank_name': bankName?.trim().isEmpty == true ? null : bankName?.trim(),
        'card_number': cardNumber?.trim().isEmpty == true ? null : cardNumber?.trim(),
        'opening_balance': openingBalance,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> updateFinancialAccount({
    required int id,
    required String name,
    required String accountKind,
    String? bankName,
    String? cardNumber,
    required int openingBalance,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('نام حساب الزامی است');
    if (openingBalance < 0) {
      throw ArgumentError('موجودی اولیه نمی‌تواند منفی باشد');
    }
    if (!const ['bank', 'cash', 'wallet', 'other'].contains(accountKind)) {
      throw ArgumentError('نوع حساب مالی نامعتبر است');
    }
    if (accountKind == 'bank' && (bankName == null || bankName.trim().isEmpty)) {
      throw ArgumentError('نام بانک را وارد کنید');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty ||
          rows.first['type'] != 'asset' ||
          rows.first['parent_id'] == null ||
          rows.first['is_system'] == 1) {
        throw StateError('این حساب مالی قابل ویرایش نیست');
      }
      final duplicate = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE name = ? AND type = ? AND parent_id = ? AND id != ?',
        [cleanName, 'asset', rows.first['parent_id'], id],
      ));
      if ((duplicate ?? 0) > 0) {
        throw StateError('حسابی با این نام در این گروه وجود دارد');
      }
      await txn.update(
        'accounts',
        {
          'name': cleanName,
          'account_kind': accountKind,
          'bank_name': accountKind == 'bank' ? bankName!.trim() : null,
          'card_number': accountKind == 'bank' &&
                  cardNumber?.trim().isNotEmpty == true
              ? cardNumber!.trim()
              : null,
          'opening_balance': openingBalance,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> renameAccount({required int id, required String name}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('نام حساب الزامی است');
    final db = await database;
    final rows =
        await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['is_system'] == 1)
      throw StateError('این حساب قابل ویرایش نیست');
    final duplicate = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM accounts WHERE name = ? AND type = ? AND id != ?',
      [cleanName, rows.first['type'], id],
    ));
    if ((duplicate ?? 0) > 0) throw StateError('حسابی با این نام وجود دارد');
    await db.update('accounts', {'name': cleanName},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAccount(int id) async {
    final db = await database;
    final rows =
        await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['is_system'] == 1)
      throw StateError('حساب اصلی یا پیش‌فرض قابل حذف نیست');
    final used = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM journal_entries WHERE account_id = ?',
      [id],
    ));
    final children = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM accounts WHERE parent_id = ?',
      [id],
    ));
    if ((used ?? 0) > 0 || (children ?? 0) > 0) {
      throw StateError('این حساب سابقه مالی یا زیرحساب دارد و قابل حذف نیست');
    }
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }
}
