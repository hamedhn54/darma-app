import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DarmaDatabase {
  DarmaDatabase._();
  static final DarmaDatabase instance = DarmaDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(p.join(root, 'darma.db'), version: 1, onCreate: (db, version) async {
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
      final asset = Sqflite.firstIntValue(await db.rawQuery("SELECT id FROM accounts WHERE type='asset'"))!;
      await db.insert('accounts', {'name': 'کیف پول نقدی', 'type': 'asset', 'parent_id': asset, 'is_system': 1, 'created_at': now});
    });
    return _db!;
  }

  Future<void> addSimpleTransaction({required String title, required int amount, required String kind}) async {
    final db = await database;
    await db.transaction((txn) async {
      final cash = Sqflite.firstIntValue(await txn.rawQuery("SELECT id FROM accounts WHERE name='کیف پول نقدی' LIMIT 1"))!;
      final rootType = kind == 'income' ? 'income' : 'expense';
      final category = Sqflite.firstIntValue(await txn.rawQuery('SELECT id FROM accounts WHERE type=? AND parent_id IS NULL LIMIT 1', [rootType]))!;
      final id = await txn.insert('journal_transactions', {'title': title, 'amount': amount, 'kind': kind, 'created_at': DateTime.now().toIso8601String()});
      if (kind == 'income') {
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': cash, 'debit': amount, 'credit': 0});
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': category, 'debit': 0, 'credit': amount});
      } else {
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': category, 'debit': amount, 'credit': 0});
        await txn.insert('journal_entries', {'transaction_id': id, 'account_id': cash, 'debit': 0, 'credit': amount});
      }
      final totals = await txn.rawQuery('SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_entries WHERE transaction_id=?', [id]);
      if ((totals.first['d'] as num) != (totals.first['c'] as num)) {
        throw StateError('سند حسابداری تراز نیست');
      }
    });
  }
}
