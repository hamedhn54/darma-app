class LedgerEntry {
  const LedgerEntry({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.personId,
  });

  final int accountId;
  final int debit;
  final int credit;
  final int? personId;

  bool get isValid =>
      accountId > 0 &&
      (personId == null || personId! > 0) &&
      debit >= 0 &&
      credit >= 0 &&
      !(debit > 0 && credit > 0) &&
      (debit > 0 || credit > 0);

  @override
  bool operator ==(Object other) =>
      other is LedgerEntry &&
      accountId == other.accountId &&
      debit == other.debit &&
      credit == other.credit &&
      personId == other.personId;

  @override
  int get hashCode => Object.hash(accountId, debit, credit, personId);
}

class LedgerDocument {
  const LedgerDocument(this.entries);

  final List<LedgerEntry> entries;

  bool get isBalanced =>
      entries.length >= 2 &&
      entries.every((entry) => entry.isValid) &&
      entries.fold<int>(0, (sum, entry) => sum + entry.debit) ==
          entries.fold<int>(0, (sum, entry) => sum + entry.credit);
}

/// Builds the balanced journal lines used by every transaction write path.
class TransactionJournal {
  static const int _maxSqliteInteger = 9223372036854775807;

  static void _validateAmounts(int amount, int fee) {
    if (amount <= 0) throw ArgumentError('مبلغ باید بیشتر از صفر باشد');
    if (fee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد');
    if (amount > _maxSqliteInteger - fee) {
      throw ArgumentError('مبلغ به همراه کارمزد از ظرفیت ذخیره‌سازی بیشتر است');
    }
  }

  static void _validateAccountId(int id) {
    if (id <= 0) throw ArgumentError('شناسه حساب نامعتبر است');
  }

  static List<LedgerEntry> income({
    required int financialAccountId,
    required int incomeAccountId,
    required int amount,
    int fee = 0,
  }) {
    _validateAmounts(amount, fee);
    _validateAccountId(financialAccountId);
    _validateAccountId(incomeAccountId);
    if (fee != 0) throw ArgumentError('برای دریافت، کارمزد مجاز نیست');
    if (financialAccountId == incomeAccountId) {
      throw ArgumentError('حساب مالی و درآمد باید متفاوت باشند');
    }
    return [
      LedgerEntry(accountId: financialAccountId, debit: amount),
      LedgerEntry(accountId: incomeAccountId, credit: amount),
    ];
  }

  static List<LedgerEntry> expense({
    required int financialAccountId,
    required int expenseAccountId,
    required int amount,
    int feeAccountId = 0,
    int fee = 0,
  }) {
    _validateAmounts(amount, fee);
    _validateAccountId(financialAccountId);
    _validateAccountId(expenseAccountId);
    if (financialAccountId == expenseAccountId) {
      throw ArgumentError('حساب مالی و هزینه باید متفاوت باشند');
    }
    if (fee > 0) {
      _validateAccountId(feeAccountId);
      if (feeAccountId == financialAccountId ||
          feeAccountId == expenseAccountId) {
        throw ArgumentError('حساب کارمزد باید از حساب مالی و هزینه جدا باشد');
      }
    }
    return [
      LedgerEntry(accountId: expenseAccountId, debit: amount),
      if (fee > 0) LedgerEntry(accountId: feeAccountId, debit: fee),
      LedgerEntry(accountId: financialAccountId, credit: amount + fee),
    ];
  }

  static List<LedgerEntry> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    int feeAccountId = 0,
    int fee = 0,
  }) {
    _validateAmounts(amount, fee);
    _validateAccountId(fromAccountId);
    _validateAccountId(toAccountId);
    if (fromAccountId == toAccountId) {
      throw ArgumentError('حساب مبدأ و مقصد باید متفاوت باشند');
    }
    if (fee > 0) {
      _validateAccountId(feeAccountId);
      if (feeAccountId == fromAccountId || feeAccountId == toAccountId) {
        throw ArgumentError('حساب کارمزد باید از حساب‌های انتقال جدا باشد');
      }
    }
    return [
      LedgerEntry(accountId: fromAccountId, credit: amount + fee),
      LedgerEntry(accountId: toAccountId, debit: amount),
      if (fee > 0) LedgerEntry(accountId: feeAccountId, debit: fee),
    ];
  }
}
