import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DarmaDatabase {
  DarmaDatabase._();
  static final DarmaDatabase instance = DarmaDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(p.join(root, 'darma.db'), version: 3, onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); }, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('asset','liability','income','expense')),
          parent_id INTEGER,
          is_system INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY(parent_id) REFERENCES accounts(id)
        )
      ''');
      await db.execute('''
        CREATE TABLE journal_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          amount INTEGER NOT NULL CHECK(amount > 0),
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
      await db.execute('CREATE INDEX idx_entries_account ON journal_entries(account_id)');
      await db.execute('CREATE INDEX idx_entries_transaction ON journal_entries(transaction_id)');
      final now = DateTime.now().toIso8601String();
      final roots = <String, String>{'دارایی‌ها':'asset','بدهی‌ها':'liability','درآمدها':'income','هزینه‌ها':'expense'};
      for (final e in roots.entries) {
        await db.insert('accounts', {'name': e.key, 'type': e.value, 'is_system': 1, 'created_at': now});
      }
      await _seedDefaultAccounts(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 3) {
        await _seedDefaultAccounts(db);
      }
    });
    return _db!;
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
      SELECT a.id, a.name, a.parent_id,
        (SELECT COUNT(*) FROM accounts child WHERE child.parent_id = a.id) AS child_count
      FROM accounts a
      WHERE a.type = ? AND a.parent_id IS NOT NULL
      ORDER BY a.parent_id, a.id
    ''', [type]);
  }

  Future<void> addSimpleTransaction({
    required String title,
    required int amount,
    required String kind,
    required int categoryAccountId,
  }) async {
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (kind != 'income' && kind != 'expense') {
      throw ArgumentError('نوع تراکنش نامعتبر است');
    }
    final db = await database;
    await db.transaction((txn) async {
      final expectedType = kind;
      final selected = await txn.query(
        'accounts',
        where: 'id = ? AND type = ? AND parent_id IS NOT NULL',
        whereArgs: [categoryAccountId, expectedType],
        limit: 1,
      );
      if (selected.isEmpty) throw StateError('حساب انتخاب‌شده معتبر نیست');
      final children = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE parent_id = ?',
        [categoryAccountId],
      ));
      if ((children ?? 0) > 0) {
        throw StateError('برای ثبت تراکنش، تفصیلی این معین را انتخاب کنید');
      }
      final cash = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT id FROM accounts WHERE name = 'کیف پول نقدی' AND type = 'asset' LIMIT 1",
      ));
      if (cash == null) throw StateError('حساب کیف پول نقدی پیدا نشد');
      final id = await txn.insert('journal_transactions', {
        'title': title,
        'amount': amount,
        'kind': kind,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (kind == 'income') {
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': cash, 'debit': amount, 'credit': 0});
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': categoryAccountId, 'debit': 0, 'credit': amount});
      } else {
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': categoryAccountId, 'debit': amount, 'credit': 0});
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': cash, 'debit': 0, 'credit': amount});
      }
      final totals = await txn.rawQuery(
        'SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_entries WHERE transaction_id=?',
        [id],
      );
      if ((totals.first['d'] as num) != (totals.first['c'] as num)) {
        throw StateError('سند حسابداری تراز نیست');
      }
    });
  }

  Future<List<Map<String, Object?>>> getTransactions() async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.id, t.title, t.amount, t.kind, t.note, t.created_at,
        e.account_id AS category_account_id, a.name AS category_name,
        CASE WHEN p.parent_id IS NULL THEN a.name ELSE p.name END AS parent_name
      FROM journal_transactions t
      JOIN journal_entries e ON e.transaction_id = t.id
      JOIN accounts a ON a.id = e.account_id AND a.type = t.kind
      LEFT JOIN accounts p ON p.id = a.parent_id
      ORDER BY t.id DESC
    ''');
  }

  Future<void> updateSimpleTransaction({
    required int transactionId,
    required String title,
    required int amount,
    required String kind,
    required int categoryAccountId,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('شرح تراکنش الزامی است');
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (kind != 'income' && kind != 'expense') throw ArgumentError('نوع تراکنش نامعتبر است');
    final db = await database;
    await db.transaction((txn) async {
      final transactionRows = await txn.query(
        'journal_transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (transactionRows.isEmpty) throw StateError('تراکنش پیدا نشد');
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
      if ((children ?? 0) > 0) throw StateError('برای ثبت تراکنش، تفصیلی را انتخاب کنید');
      final cash = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT id FROM accounts WHERE name = 'کیف پول نقدی' AND type = 'asset' LIMIT 1",
      ));
      if (cash == null) throw StateError('حساب کیف پول نقدی پیدا نشد');
      await txn.update(
        'journal_transactions',
        {'title': title.trim(), 'amount': amount, 'kind': kind},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      await txn.delete('journal_entries', where: 'transaction_id = ?', whereArgs: [transactionId]);
      if (kind == 'income') {
        await txn.insert('journal_entries', {'transaction_id': transactionId, 'account_id': cash, 'debit': amount, 'credit': 0});
        await txn.insert('journal_entries', {'transaction_id': transactionId, 'account_id': categoryAccountId, 'debit': 0, 'credit': amount});
      } else {
        await txn.insert('journal_entries', {'transaction_id': transactionId, 'account_id': categoryAccountId, 'debit': amount, 'credit': 0});
        await txn.insert('journal_entries', {'transaction_id': transactionId, 'account_id': cash, 'debit': 0, 'credit': amount});
      }
    });
  }

  Future<void> deleteTransaction(int transactionId) async {
    final db = await database;
    await db.transaction((txn) async {
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM journal_transactions WHERE id = ?',
        [transactionId],
      ));
      if ((count ?? 0) == 0) throw StateError('تراکنش پیدا نشد');
      await txn.delete('journal_entries', where: 'transaction_id = ?', whereArgs: [transactionId]);
      await txn.delete('journal_transactions', where: 'id = ?', whereArgs: [transactionId]);
    });
  }

  Future<List<Map<String, Object?>>> getAccountSummaries() async {
    final db = await database;
    return db.rawQuery('''
      SELECT a.id, a.name, a.type, a.parent_id, a.is_system,
        (SELECT root.id FROM accounts root WHERE root.type = a.type AND root.parent_id IS NULL LIMIT 1) AS root_id,
        CASE
          WHEN a.type IN ('asset','expense')
            THEN COALESCE(SUM(e.debit - e.credit), 0)
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
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('نام حساب الزامی است');
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
        final parents = await txn.query('accounts', where: 'id = ?', whereArgs: [parentId], limit: 1);
        if (parents.isEmpty || parents.first['type'] != type) {
          throw StateError('حساب معین معتبر نیست');
        }
        final parentParentId = parents.first['parent_id'];
        if (parentParentId == null) throw StateError('امکان ایجاد تفصیلی زیر سرفصل اصلی وجود ندارد');
        targetParent = parentId;
      }
      final duplicate = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE name = ? AND type = ? AND parent_id = ?',
        [cleanName, type, targetParent],
      ));
      if ((duplicate ?? 0) > 0) throw StateError('حسابی با این نام در این گروه وجود دارد');
      return txn.insert('accounts', {
        'name': cleanName,
        'type': type,
        'parent_id': targetParent,
        'is_system': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> renameAccount({required int id, required String name}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('نام حساب الزامی است');
    final db = await database;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['is_system'] == 1) {
      throw StateError('این حساب قابل ویرایش نیست');
    }
    final duplicate = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM accounts WHERE name = ? AND type = ? AND id != ?',
      [cleanName, rows.first['type'], id],
    ));
    if ((duplicate ?? 0) > 0) throw StateError('حسابی با این نام وجود دارد');
    await db.update('accounts', {'name': cleanName}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAccount(int id) async {
    final db = await database;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['is_system'] == 1) {
      throw StateError('حساب اصلی یا پیش‌فرض قابل حذف نیست');
    }
    final used = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM journal_entries WHERE account_id = ?', [id],
    ));
    final children = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM accounts WHERE parent_id = ?', [id],
    ));
    if ((used ?? 0) > 0 || (children ?? 0) > 0) {
      throw StateError('این حساب سابقه مالی یا زیرحساب دارد و قابل حذف نیست');
    }
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

}
