import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'data/darma_database.dart';
import 'presentation/accounts_page.dart';
import 'presentation/reports_page.dart';
import 'presentation/widgets/amount_calculator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DarmaDatabase.instance.database;
  runApp(const DarmaApp());
}

const _themes = <String, Color>{
  'Executive Dark': Color(0xFF101827),
  'Executive Light': Color(0xFFF3F5F8),
  'Emerald': Color(0xFF0B3028),
  'Royal Purple': Color(0xFF281B3D),
  'Graphite': Color(0xFF25282E),
};

class DarmaApp extends StatefulWidget {
  const DarmaApp({super.key});
  @override
  State<DarmaApp> createState() => _DarmaAppState();
}

class _DarmaAppState extends State<DarmaApp> {
  String _theme = 'Executive Dark';

  @override
  Widget build(BuildContext context) {
    final dark = _theme != 'Executive Light';
    final seed = _themes[_theme]!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دارما',
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        scaffoldBackgroundColor:
            dark ? const Color(0xFF0B1220) : const Color(0xFFF4F6FA),
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
      home: DarmaHome(
        themeName: _theme,
        onThemeChanged: (v) => setState(() => _theme = v),
      ),
    );
  }
}

class DarmaHome extends StatefulWidget {
  const DarmaHome(
      {super.key, required this.themeName, required this.onThemeChanged});
  final String themeName;
  final ValueChanged<String> onThemeChanged;

  @override
  State<DarmaHome> createState() => _DarmaHomeState();
}

class _DarmaHomeState extends State<DarmaHome> {
  int _tab = 0;
  int _balance = 0;
  List<Map<String, Object?>> _cashAccounts = [];
  int? _selectedCashAccountId;
  DateTime? _selectedTransactionDate;
  List<Map<String, Object?>> _recent = [];
  List<Map<String, Object?>> _transactions = [];
  final _money = NumberFormat('#,###', 'en_US');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = await DarmaDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.id, a.name, a.account_kind, a.bank_name,
        COALESCE(a.opening_balance, 0) +
          COALESCE(SUM(e.debit - e.credit), 0) AS raw_balance
      FROM accounts a
      LEFT JOIN journal_entries e ON e.account_id = a.id
      WHERE a.type = 'asset'
        AND a.parent_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM accounts child WHERE child.parent_id = a.id)
        AND (
          a.account_kind IS NOT NULL
          OR a.name IN ('کیف پول نقدی', 'حساب بانکی', 'کیف پول الکترونیکی')
        )
      GROUP BY a.id
      ORDER BY a.parent_id, a.id
    ''');
    final total = rows.fold<int>(
        0, (s, r) => s + ((r['raw_balance'] as num?)?.toInt() ?? 0));
    final recent = await db.rawQuery(
      'SELECT id, title, amount, fee, kind, created_at FROM journal_transactions ORDER BY id DESC LIMIT 5',
    );
    final transactions = await DarmaDatabase.instance.getTransactions();
    if (mounted) {
      setState(() {
        _cashAccounts = rows;
        if (_selectedCashAccountId != null &&
            !rows.any((r) => r['id'] == _selectedCashAccountId)) {
          _selectedCashAccountId = null;
        }
        _balance = total;
        _recent = recent;
        _transactions = transactions;
      });
    }
  }

  String _digits(String s) => s
      .replaceAll('0', '۰')
      .replaceAll('1', '۱')
      .replaceAll('2', '۲')
      .replaceAll('3', '۳')
      .replaceAll('4', '۴')
      .replaceAll('5', '۵')
      .replaceAll('6', '۶')
      .replaceAll('7', '۷')
      .replaceAll('8', '۸')
      .replaceAll('9', '۹');

  String _moneyText(int v) => _digits(_money.format(v));

  int get _displayBalance {
    if (_selectedCashAccountId == null) return _balance;
    final account = _cashAccounts.firstWhere(
      (a) => a['id'] == _selectedCashAccountId,
      orElse: () => const <String, Object?>{},
    );
    return (account['raw_balance'] as num?)?.toInt() ?? 0;
  }

  List<Map<String, Object?>> get _visibleTransactions {
    final selected = _selectedTransactionDate;
    if (selected == null) return _transactions;
    return _transactions.where((transaction) {
      final raw = transaction['created_at'] as String?;
      if (raw == null) return false;
      final date = DateTime.tryParse(raw)?.toLocal();
      return date != null && date.year == selected.year &&
          date.month == selected.month && date.day == selected.day;
    }).toList();
  }

  String _jalaliDateLabel(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${_digits(j.year.toString())}/${_digits(j.month.toString().padLeft(2, '0'))}/${_digits(j.day.toString().padLeft(2, '0'))}';
  }

  String _transactionDateText(Object? rawDate) {
    if (rawDate is! String) return '';
    final date = DateTime.tryParse(rawDate)?.toLocal();
    return date == null ? '' : _jalaliDateLabel(date);
  }

  Future<void> _pickTransactionDate() async {
    final now = Jalali.now();
    final initial = _selectedTransactionDate == null
        ? now : Jalali.fromDateTime(_selectedTransactionDate!);
    final picked = await showModalBottomSheet<DateTime>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) {
        var month = initial.month;
        var year = initial.year;
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            const monthNames = [
              'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
              'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
            ];
            final firstDay = Jalali(year, month, 1).toDateTime();
            final leading = (firstDay.weekday + 1) % 7;
            final monthLength = Jalali(year, month, 1).monthLength;
            final cells = <int?>[
              ...List<int?>.filled(leading, null),
              ...List<int>.generate(monthLength, (i) => i + 1),
            ];
            while (cells.length % 7 != 0) { cells.add(null); }
            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => setSheet(() {
                              if (month == 1) { month = 12; year--; } else { month--; }
                            }),
                            icon: const Icon(Icons.chevron_right)),
                          Text('${monthNames[month - 1]} ${_digits(year.toString())}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          IconButton(
                            onPressed: () => setSheet(() {
                              if (month == 12) { month = 1; year++; } else { month++; }
                            }),
                            icon: const Icon(Icons.chevron_left)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
                          .map((day) => Expanded(child: Center(
                            child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold)))))
                          .toList(),
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cells.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5),
                        itemBuilder: (context, index) {
                          final day = cells[index];
                          if (day == null) return const SizedBox.shrink();
                          final selectedDate = _selectedTransactionDate == null
                              ? null : Jalali.fromDateTime(_selectedTransactionDate!);
                          final selected = selectedDate != null &&
                              selectedDate.year == year && selectedDate.month == month &&
                              selectedDate.day == day;
                          return InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => Navigator.pop(sheetContext,
                              Jalali(year, month, day).toDateTime()),
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected ? Theme.of(context).colorScheme.primary : null,
                                shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: Text(_digits(day.toString()),
                                style: TextStyle(
                                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                  color: selected ? Theme.of(context).colorScheme.onPrimary : null)),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext, DateTime(1900, 1, 1)),
                        child: const Text('پاک کردن فیلتر تاریخ')),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedTransactionDate =
          picked.year == 1900 ? null : DateTime(picked.year, picked.month, picked.day));
    }
  }

  int _parseAmount(String value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var normalized = value;
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    normalized =
        normalized.replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
    return int.tryParse(normalized) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _transactionsPage(),
      const ReportsPage(),
      _morePage(),
    ];
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded),
              SizedBox(width: 9),
              Text('دارما', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          actions: [
            IconButton(
                onPressed: _showThemes,
                icon: const Icon(Icons.palette_outlined)),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
        floatingActionButton: _tab == 0 || _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => _newTransaction(),
                icon: const Icon(Icons.add),
                label: const Text('ثبت تراکنش'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (v) => setState(() => _tab = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'خانه'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'تراکنش‌ها'),
            NavigationDestination(
                icon: Icon(Icons.query_stats_outlined),
                selectedIcon: Icon(Icons.query_stats),
                label: 'گزارش‌ها'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                selectedIcon: Icon(Icons.grid_view),
                label: 'بیشتر'),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          children: [
            Text(
              'نمای کلی دارایی',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('موجودی خالص حساب‌های نقدی'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: _selectedCashAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'نمایش موجودی',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('همه حساب‌ها')),
                      ..._cashAccounts.map((account) => DropdownMenuItem<int?>(
                        value: account['id'] as int,
                        child: Text(
                          '${account['name']}${account['bank_name'] == null ? '' : ' • ${account['bank_name']}'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                    ],
                    onChanged: (value) => setState(() => _selectedCashAccountId = value),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${_moneyText(_displayBalance)} ریال',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text('ذخیره‌سازی محلی روی همین دستگاه',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _actionTile('دریافت', Icons.south_west_rounded,
                      Colors.green, () => _newTransaction(kind: 'income')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionTile('پرداخت', Icons.north_east_rounded,
                      Colors.redAccent, () => _newTransaction(kind: 'expense')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionTile('انتقال', Icons.sync_alt_rounded,
                      Colors.orange, () => _newTransfer()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'آخرین تراکنش‌ها',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: const Text('مشاهده همه'),
                ),
              ],
            ),
            if (_recent.isEmpty)
              const _EmptyState(text: 'هنوز تراکنشی ثبت نشده است')
            else
              ..._recent.map((r) => _recentTile(r)),
          ],
        ),
      );

  Widget _recentTile(Map<String, Object?> r) {
    final kind = r['kind'] as String;
    final transfer = kind == 'transfer';
    final income = kind == 'income';
    final fee = (r['fee'] as num?)?.toInt() ?? 0;
    final date = _transactionDateText(r['created_at']);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (transfer
                  ? Colors.orange
                  : income
                      ? Colors.green
                      : Colors.red)
              .withValues(alpha: 0.14),
          child: Icon(
            transfer
                ? Icons.sync_alt
                : income
                    ? Icons.south_west
                    : Icons.north_east,
            color: transfer
                ? Colors.orange
                : income
                    ? Colors.green
                    : Colors.red,
          ),
        ),
        title: Text(r['title'] as String),
        subtitle: Text(
          '${transfer ? 'انتقال وجه' : income ? 'دریافت' : 'پرداخت'}'
          '${date.isNotEmpty ? ' • $date' : ''}'
          '${fee > 0 ? ' • کارمزد: ${_moneyText(fee)} ریال' : ''}',
        ),
        trailing: Text(
          '${_moneyText((r['amount'] as num).toInt())} ریال',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _actionTile(
          String title, IconData icon, Color color, VoidCallback tap) =>
      InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(18),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );

  Widget _transactionsPage() => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
          itemCount: _visibleTransactions.isEmpty ? 2 : _visibleTransactions.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: Text(_selectedTransactionDate == null
                      ? 'همه تاریخ‌ها'
                      : 'تراکنش‌های ${_jalaliDateLabel(_selectedTransactionDate!)}'),
                  subtitle: const Text('برای انتخاب روز موردنظر لمس کنید'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedTransactionDate != null)
                        IconButton(
                          tooltip: 'حذف فیلتر تاریخ',
                          onPressed: () => setState(() => _selectedTransactionDate = null),
                          icon: const Icon(Icons.close),
                        ),
                      const Icon(Icons.date_range_outlined),
                    ],
                  ),
                  onTap: _pickTransactionDate,
                ),
              );
            }
            if (_visibleTransactions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 110),
                child: _EmptyState(
                  text: _selectedTransactionDate == null
                    ? 'هنوز تراکنشی ثبت نشده است'
                    : 'در این روز تراکنشی ثبت نشده است',
                ),
              );
            }
            final transaction = _visibleTransactions[index - 1];
            final kind = transaction['kind'] as String;
            final income = kind == 'income';
            final transfer = kind == 'transfer';
            final fee = (transaction['fee'] as num?)?.toInt() ?? 0;
            final date = _transactionDateText(transaction['created_at']);
            final dateLabel = date.isNotEmpty ? ' • $date' : '';
            final subtitle = transfer
                ? 'انتقال وجه$dateLabel\\n'
                    '${transaction['from_account_name'] ?? 'مبدأ'} ← ${transaction['to_account_name'] ?? 'مقصد'}\\n'
                    '${_moneyText((transaction['amount'] as num).toInt())} ریال'
                    '${fee > 0 ? ' • کارمزد: ${_moneyText(fee)} ریال' : ''}'
                : '${income ? 'دریافت' : 'پرداخت'}$dateLabel • '
                    '${transaction['parent_name'] ?? transaction['category_name']}\\n'
                    'حساب: ${transaction['financial_account_name'] ?? 'کیف پول نقدی'}\\n'
                    '${_moneyText((transaction['amount'] as num).toInt())} ریال'
                    '${fee > 0 ? ' • کارمزد: ${_moneyText(fee)} ریال' : ''}';
            return Card(
              child: ListTile(
                onTap: transfer
                    ? () => _newTransfer(existing: transaction)
                    : () => _newTransaction(existing: transaction),
                leading: CircleAvatar(
                  backgroundColor: (transfer ? Colors.orange : income ? Colors.green : Colors.red)
                      .withValues(alpha: 0.14),
                  child: Icon(
                    transfer ? Icons.sync_alt : income ? Icons.south_west : Icons.north_east,
                    color: transfer ? Colors.orange : income ? Colors.green : Colors.red,
                  ),
                ),
                title: Text(transaction['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(subtitle),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      if (transfer) {
                        await _newTransfer(existing: transaction);
                      } else {
                        await _newTransaction(existing: transaction);
                      }
                    } else if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('حذف تراکنش'),
                          content: Text(
                            'تراکنش «${transaction['title']}» حذف شود؟ این عملیات قابل بازگشت نیست.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('انصراف')),
                            FilledButton.tonal(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('حذف')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await DarmaDatabase.instance.deleteTransaction(transaction['id'] as int);
                          await _refresh();
                        } catch (error) {
                          _notice(error.toString());
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );
          },
        ),
      );

  Widget _simplePage(String title, IconData icon, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _morePage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'امکانات دارما',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final item in [
            ('تعاریف و حساب‌ها', Icons.account_tree_outlined),
            ('اشخاص', Icons.people_outline),
            ('وام‌ها و تسهیلات', Icons.handshake_outlined),
            ('خریدهای اعتباری', Icons.credit_card),
            ('بودجه‌بندی', Icons.pie_chart_outline),
            ('اهداف مالی', Icons.flag_outlined),
            ('تقویم مالی', Icons.calendar_month_outlined),
            ('تنظیمات', Icons.settings_outlined),
          ])
            Card(
              child: ListTile(
                leading: Icon(item.$2),
                title: Text(item.$1),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  if (item.$1 == 'تعاریف و حساب‌ها') {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AccountsPage()));
                  } else if (item.$1 == 'تنظیمات') {
                    _showThemes();
                  } else {
                    _notice('بخش ${item.$1} در نسخه‌های بعدی فعال می‌شود.');
                  }
                },
              ),
            ),
        ],
      );

  void _showThemes() => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('انتخاب پوسته',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                for (final name in _themes.keys)
                  ListTile(
                    leading: CircleAvatar(backgroundColor: _themes[name]),
                    title: Text(name),
                    trailing: widget.themeName == name
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () {
                      widget.onThemeChanged(name);
                      Navigator.pop(context);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );

  Future<DateTime?> _showJalaliDatePicker(DateTime initialDate) async {
    final initial = Jalali.fromDateTime(initialDate);
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var year = initial.year;
        var month = initial.month;
        var selectedDay = initial.day;
        const monthNames = [
          'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
          'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
        ];
        return StatefulBuilder(
          builder: (context, setSheet) {
            final firstDay = Jalali(year, month, 1).toDateTime();
            final leading = (firstDay.weekday + 1) % 7;
            final monthLength = Jalali(year, month, 1).monthLength;
            final cells = <int?>[
              ...List<int?>.filled(leading, null),
              ...List<int>.generate(monthLength, (index) => index + 1),
            ];
            while (cells.length % 7 != 0) {
              cells.add(null);
            }
            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => setSheet(() {
                              if (month == 1) {
                                month = 12;
                                year--;
                              } else {
                                month--;
                              }
                            }),
                            icon: const Icon(Icons.chevron_right),
                          ),
                          Text(
                            '${monthNames[month - 1]} ${_digits(year.toString())}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setSheet(() {
                              if (month == 12) {
                                month = 1;
                                year++;
                              } else {
                                month++;
                              }
                            }),
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
                            .map((day) => Expanded(
                                  child: Center(
                                    child: Text(
                                      day,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cells.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                        ),
                        itemBuilder: (context, index) {
                          final day = cells[index];
                          if (day == null) {
                            return const SizedBox.shrink();
                          }
                          final selected = selectedDay == day;
                          return InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => setSheet(() => selectedDay = day),
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _digits(day.toString()),
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selected
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            Jalali(year, month, selectedDay).toDateTime(),
                          ),
                          child: const Text('تأیید تاریخ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _transactionDateField(DateTime date, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.calendar_month_rounded),
        title: const Text('تاریخ تراکنش'),
        subtitle: Text(_jalaliDateLabel(date)),
        trailing: const Icon(Icons.edit_calendar_outlined),
      ),
    );
  }

  Future<void> _newTransfer({Map<String, Object?>? existing}) async {
    final allAssets =
        await DarmaDatabase.instance.getTransactionAccounts('asset');
    final assets =
        allAssets.where((a) => (a['child_count'] as num).toInt() == 0).toList();
    if (assets.length < 2) {
      _notice('برای انتقال، حداقل دو حساب دارایی تعریف کنید.');
      return;
    }

    int fromId =
        existing?['from_account_id'] as int? ?? assets.first['id'] as int;
    int toId = existing?['to_account_id'] as int? ??
        assets.firstWhere((a) => a['id'] != fromId)['id'] as int;
    if (toId == fromId) {
      toId = assets.firstWhere((a) => a['id'] != fromId)['id'] as int;
    }

    final title = TextEditingController(
        text: existing?['title'] as String? ?? 'انتقال وجه');
    final amount = TextEditingController(
      text: existing == null ? '' : (existing['amount'] as num).toString(),
    );
    final fee = TextEditingController(
      text: existing == null
          ? ''
          : ((existing['fee'] as num?)?.toInt() ?? 0).toString(),
    );
    final formKey = GlobalKey<FormState>();
    var transactionDate = DateTime.tryParse(existing?['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now();
    transactionDate = DateTime(transactionDate.year, transactionDate.month, transactionDate.day, 12);
    var isSaving = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null ? 'انتقال بین حساب‌ها' : 'ویرایش انتقال',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _transactionDateField(transactionDate, () async {
                      final picked = await _showJalaliDatePicker(transactionDate);
                      if (picked != null) {
                        setSheet(() => transactionDate = DateTime(picked.year, picked.month, picked.day, 12));
                      }
                    }),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: fromId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'حساب مبدأ (برداشت از)',
                        border: OutlineInputBorder(),
                      ),
                      items: assets
                          .map((a) => DropdownMenuItem<int>(
                                value: a['id'] as int,
                                child: Text(a['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setSheet(() {
                          fromId = v;
                          if (toId == fromId) {
                            toId = assets.firstWhere(
                                (a) => a['id'] != fromId)['id'] as int;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('transfer-to-$fromId-$toId'),
                      value: toId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'حساب مقصد (واریز به)',
                        border: OutlineInputBorder(),
                      ),
                      items: assets
                          .where((a) => a['id'] != fromId)
                          .map((a) => DropdownMenuItem<int>(
                                value: a['id'] as int,
                                child: Text(a['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setSheet(() {
                        if (v != null) toId = v;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'شرح انتقال',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'شرح را وارد کنید'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    AmountCalculatorField(
                      controller: amount,
                      label: 'مبلغ انتقال به ریال',
                      validator: (v) => _parseAmount(v ?? '') <= 0
                          ? 'مبلغ معتبر وارد کنید'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    AmountCalculatorField(
                      controller: fee,
                      label: 'کارمزد بانکی (اختیاری)',
                      validator: (v) {
                        final value = _parseAmount(v ?? '');
                        if (value < 0) return 'کارمزد معتبر وارد کنید';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                        if (isSaving || !formKey.currentState!.validate()) return;
                        setSheet(() => isSaving = true);
                        try {
                          final feeValue = _parseAmount(fee.text);
                          if (existing == null) {
                            await DarmaDatabase.instance.addTransfer(
                              title: title.text.trim(),
                              amount: _parseAmount(amount.text),
                              fromAccountId: fromId,
                              toAccountId: toId,
                              fee: feeValue,
                              transactionDate: transactionDate,
                            );
                          } else {
                            await DarmaDatabase.instance.updateTransfer(
                              transactionId: existing['id'] as int,
                              title: title.text.trim(),
                              amount: _parseAmount(amount.text),
                              fromAccountId: fromId,
                              toAccountId: toId,
                              fee: feeValue,
                              transactionDate: transactionDate,
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (error) {
                          if (ctx.mounted) {
                            setSheet(() => isSaving = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(error
                                    .toString()
                                    .replaceFirst('Exception: ', '')),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.sync_alt),
                      label: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(existing == null ? 'ثبت انتقال' : 'ذخیره تغییرات'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    title.dispose();
    amount.dispose();
    fee.dispose();
    if (result == true) await _refresh();
  }

  Future<void> _newTransaction(
      {String? kind, Map<String, Object?>? existing}) async {
    String selected = kind ?? (existing?['kind'] as String? ?? 'expense');
    if (selected == 'transfer') selected = 'expense';
    final accounts = await DarmaDatabase.instance.getAccountSummaries();
    final financialAccounts = (await DarmaDatabase.instance.getTransactionAccounts('asset'))
        .where((a) {
          final isLeaf = (a['child_count'] as num).toInt() == 0;
          final kind = a['account_kind'] as String?;
          final legacyFinancial = const {
            'کیف پول نقدی',
            'حساب بانکی',
            'کیف پول الکترونیکی',
          }.contains(a['name']);
          return isLeaf && (kind != null || legacyFinancial);
        })
        .toList();
    if (financialAccounts.isEmpty) {
      _notice('ابتدا یک حساب بانکی، صندوق یا کیف پول در بخش تعاریف ایجاد کنید.');
      return;
    }
    int selectedFinancialAccountId =
        existing?['financial_account_id'] as int? ??
        financialAccounts.first['id'] as int;
    if (!financialAccounts.any((a) => a['id'] == selectedFinancialAccountId)) {
      selectedFinancialAccountId = financialAccounts.first['id'] as int;
    }
    List<Map<String, Object?>> categoryAccounts(String type) => accounts
        .where((a) => a['type'] == type && a['parent_id'] == a['root_id'])
        .toList();
    final initialMains = categoryAccounts(selected);
    if (initialMains.isEmpty) {
      _notice('ابتدا برای این سرفصل یک حساب معین تعریف کنید.');
      return;
    }

    final oldCategoryId = existing?['category_account_id'] as int?;
    final oldCategoryMatches = oldCategoryId == null
        ? <Map<String, Object?>>[]
        : accounts.where((a) => a['id'] == oldCategoryId).toList();
    final oldCategory =
        oldCategoryMatches.isEmpty ? null : oldCategoryMatches.first;

    int selectedMainId = oldCategory == null
        ? initialMains.first['id'] as int
        : (oldCategory['parent_id'] == oldCategory['root_id']
            ? oldCategory['id'] as int
            : oldCategory['parent_id'] as int);

    List<Map<String, Object?>> detailsFor(int mainId) => accounts
        .where((a) => a['type'] == selected && a['parent_id'] == mainId)
        .toList();

    int? selectedDetailId = oldCategory != null &&
            oldCategory['parent_id'] != oldCategory['root_id']
        ? oldCategoryId
        : (detailsFor(selectedMainId).isEmpty
            ? null
            : detailsFor(selectedMainId).first['id'] as int);

    final title =
        TextEditingController(text: existing?['title'] as String? ?? '');
    final amount = TextEditingController(
      text: existing == null ? '' : (existing['amount'] as num).toString(),
    );
    final fee = TextEditingController(
      text: existing == null
          ? ''
          : ((existing['fee'] as num?)?.toInt() ?? 0).toString(),
    );
    final formKey = GlobalKey<FormState>();
    var transactionDate = DateTime.tryParse(existing?['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now();
    transactionDate = DateTime(transactionDate.year, transactionDate.month, transactionDate.day, 12);
    var isSaving = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final mains = categoryAccounts(selected);
          final details = detailsFor(selectedMainId);
          final selectedCategoryId =
              details.isEmpty ? selectedMainId : selectedDetailId;
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        existing == null ? 'تراکنش جدید' : 'ویرایش تراکنش',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'income',
                              label: Text('دریافت'),
                              icon: Icon(Icons.south_west)),
                          ButtonSegment(
                              value: 'expense',
                              label: Text('پرداخت'),
                              icon: Icon(Icons.north_east)),
                        ],
                        selected: {selected},
                        onSelectionChanged: (v) {
                          setSheet(() {
                            selected = v.first;
                            final nextMains = categoryAccounts(selected);
                            selectedMainId = nextMains.first['id'] as int;
                            final nextDetails = detailsFor(selectedMainId);
                            selectedDetailId = nextDetails.isEmpty
                                ? null
                                : nextDetails.first['id'] as int;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _transactionDateField(transactionDate, () async {
                        final picked = await _showJalaliDatePicker(transactionDate);
                        if (picked != null) {
                          setSheet(() => transactionDate = DateTime(picked.year, picked.month, picked.day, 12));
                        }
                      }),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: selectedFinancialAccountId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: selected == 'income'
                              ? 'واریز به حساب'
                              : 'پرداخت از حساب',
                          border: const OutlineInputBorder(),
                        ),
                        items: financialAccounts.map((a) {
                          final bank = (a['bank_name'] as String?)?.trim();
                          final balance = (a['balance'] as num?)?.toInt() ?? 0;
                          final label = [
                            a['name'] as String,
                            if (bank != null && bank.isNotEmpty) bank,
                            'مانده ${_moneyText(balance)}',
                          ].join(' • ');
                          return DropdownMenuItem<int>(
                            value: a['id'] as int,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setSheet(() => selectedFinancialAccountId = value);
                          }
                        },
                        validator: (value) =>
                            value == null ? 'حساب مالی را انتخاب کنید' : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        key: ValueKey('main-$selectedMainId'),
                        value: selectedMainId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'حساب معین',
                            border: OutlineInputBorder()),
                        items: mains
                            .map((a) => DropdownMenuItem<int>(
                                  value: a['id'] as int,
                                  child: Text(a['name'] as String,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setSheet(() {
                            selectedMainId = value;
                            final nextDetails = detailsFor(value);
                            selectedDetailId = nextDetails.isEmpty
                                ? null
                                : nextDetails.first['id'] as int;
                          });
                        },
                        validator: (_) => selectedMainId > 0
                            ? null
                            : 'حساب معین را انتخاب کنید',
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: ValueKey(
                              'detail-$selectedMainId-$selectedDetailId'),
                          value: selectedDetailId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'حساب تفصیلی',
                              border: OutlineInputBorder()),
                          items: details
                              .map((a) => DropdownMenuItem<int>(
                                    value: a['id'] as int,
                                    child: Text(a['name'] as String,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              setSheet(() => selectedDetailId = value),
                          validator: (value) => value == null
                              ? 'حساب تفصیلی را انتخاب کنید'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: title,
                        decoration: const InputDecoration(
                            labelText: 'شرح تراکنش',
                            border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'شرح را وارد کنید'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      AmountCalculatorField(
                        controller: amount,
                        label: 'مبلغ به ریال',
                        validator: (v) => _parseAmount(v ?? '') <= 0
                            ? 'مبلغ معتبر وارد کنید'
                            : null,
                      ),
                      if (selected == 'expense') ...[
                        const SizedBox(height: 12),
                        AmountCalculatorField(
                          controller: fee,
                          label: 'کارمزد بانکی (اختیاری)',
                          validator: (v) {
                            final value = _parseAmount(v ?? '');
                            if (value < 0) return 'کارمزد معتبر وارد کنید';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                          if (isSaving ||
                              !formKey.currentState!.validate() ||
                              selectedCategoryId == null) return;
                          setSheet(() => isSaving = true);
                          try {
                            final feeValue = selected == 'expense'
                                ? _parseAmount(fee.text)
                                : 0;
                            if (existing == null) {
                              await DarmaDatabase.instance.addSimpleTransaction(
                                title: title.text.trim(),
                                amount: _parseAmount(amount.text),
                                kind: selected,
                                categoryAccountId: selectedCategoryId,
                                financialAccountId: selectedFinancialAccountId,
                                fee: feeValue,
                                transactionDate: transactionDate,
                              );
                            } else {
                              await DarmaDatabase.instance
                                  .updateSimpleTransaction(
                                transactionId: existing['id'] as int,
                                title: title.text.trim(),
                                amount: _parseAmount(amount.text),
                                kind: selected,
                                categoryAccountId: selectedCategoryId,
                                financialAccountId: selectedFinancialAccountId,
                                fee: feeValue,
                                transactionDate: transactionDate,
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (error) {
                            if (ctx.mounted) {
                              setSheet(() => isSaving = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(error
                                      .toString()
                                      .replaceFirst('Exception: ', '')),
                                ),
                              );
                            }
                          }
                        },
                        child: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(existing == null ? 'ثبت تراکنش' : 'ذخیره تغییرات'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    title.dispose();
    amount.dispose();
    fee.dispose();
    if (result == true) await _refresh();
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
