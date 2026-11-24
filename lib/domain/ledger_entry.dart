class LedgerEntry {
  const LedgerEntry({required this.accountId, this.debit = 0, this.credit = 0});

  final int accountId;
  final int debit;
  final int credit;

  bool get isValid =>
      accountId > 0 &&
      debit >= 0 &&
      credit >= 0 &&
      !(debit > 0 && credit > 0) &&
      (debit > 0 || credit > 0);
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
