import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'data/darma_database.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: dark ? Brightness.dark : Brightness.light),
        scaffoldBackgroundColor: dark ? const Color(0xFF0B1220) : const Color(0xFFF4F6FA),
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
      ),
      home: DarmaHome(themeName: _theme, onThemeChanged: (v) => setState(() => _theme = v)),
    );
  }
}

class DarmaHome extends StatefulWidget {
  const DarmaHome({super.key, required this.themeName, required this.onThemeChanged});
  final String themeName;
  final ValueChanged<String> onThemeChanged;
  @override
  State<DarmaHome> createState() => _DarmaHomeState();
}

class _DarmaHomeState extends State<DarmaHome> {
  int _tab = 0;
  int _balance = 0;
  List<Map<String, Object?>> _recent = [];
  final _money = NumberFormat('#,###', 'en_US');

  @override
  void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    final db = await DarmaDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.id, a.name, a.type,
      COALESCE(SUM(e.debit - e.credit), 0) AS raw_balance
      FROM accounts a LEFT JOIN journal_entries e ON e.account_id = a.id
      WHERE a.type = 'asset' AND a.parent_id IS NOT NULL
      GROUP BY a.id
    ''');
    final total = rows.fold<int>(0, (s, r) => s + ((r['raw_balance'] as num?)?.toInt() ?? 0));
    final recent = await db.rawQuery('SELECT id, title, amount, kind, created_at FROM journal_transactions ORDER BY id DESC LIMIT 5');
    if (mounted) setState(() { _balance = total; _recent = recent; });
  }

  String _digits(String s) => s.replaceAll('0','۰').replaceAll('1','۱').replaceAll('2','۲').replaceAll('3','۳').replaceAll('4','۴').replaceAll('5','۵').replaceAll('6','۶').replaceAll('7','۷').replaceAll('8','۸').replaceAll('9','۹');
  String _moneyText(int v) => _digits(_money.format(v));

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _simplePage('تراکنش‌ها', Icons.swap_horiz_rounded, 'ثبت‌ها و گردش مالی شما در این بخش نمایش داده می‌شود.'),
      _simplePage('گزارش‌ها', Icons.insights_rounded, 'گزارش‌های درآمد، هزینه و مانده حساب در حال آماده‌سازی است.'),
      _morePage(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(children: [Icon(Icons.account_balance_wallet_rounded), SizedBox(width: 9), Text('دارما', style: TextStyle(fontWeight: FontWeight.w800))]),
          actions: [IconButton(onPressed: _showThemes, icon: const Icon(Icons.palette_outlined)), const SizedBox(width: 8)],
        ),
        body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
        floatingActionButton: _tab == 0 || _tab == 1 ? FloatingActionButton.extended(onPressed: _newTransaction, icon: const Icon(Icons.add), label: const Text('ثبت تراکنش')) : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (v) => setState(() => _tab = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'تراکنش‌ها'),
            NavigationDestination(icon: Icon(Icons.query_stats_outlined), selectedIcon: Icon(Icons.query_stats), label: 'گزارش‌ها'),
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view), label: 'بیشتر'),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 100), children: [
      Text('نمای کلی دارایی', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.surfaceContainerHighest], begin: Alignment.topRight, end: Alignment.bottomLeft),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('موجودی خالص حساب‌های نقدی'),
          const SizedBox(height: 12),
          Text('${_moneyText(_balance)} ریال', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('ذخیره‌سازی محلی روی همین دستگاه', style: TextStyle(fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: _actionTile('دریافت', Icons.south_west_rounded, Colors.green, () => _newTransaction(kind: 'income'))),
        const SizedBox(width: 10),
        Expanded(child: _actionTile('پرداخت', Icons.north_east_rounded, Colors.redAccent, () => _newTransaction(kind: 'expense'))),
        const SizedBox(width: 10),
        Expanded(child: _actionTile('انتقال', Icons.sync_alt_rounded, Colors.orange, () => _notice('ثبت انتقال در گام بعدی فعال می‌شود.'))),
      ]),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('آخرین تراکنش‌ها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('مشاهده همه')),
      ]),
      if (_recent.isEmpty) const _EmptyState(text: 'هنوز تراکنشی ثبت نشده است')
      else ..._recent.map((r) => Card(child: ListTile(
        leading: CircleAvatar(child: Icon(r['kind'] == 'income' ? Icons.south_west : Icons.north_east)),
        title: Text(r['title'] as String),
        subtitle: Text((r['kind'] == 'income' ? 'دریافت' : 'پرداخت')),
        trailing: Text('${_moneyText((r['amount'] as num).toInt())} ریال', style: const TextStyle(fontWeight: FontWeight.bold)),
      ))),
    ]),
  );

  Widget _actionTile(String title, IconData icon, Color color, VoidCallback tap) => Expanded(
    child: InkWell(onTap: tap, borderRadius: BorderRadius.circular(18), child: Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Column(children: [Icon(icon, color: color), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))])))),
  );

  Widget _simplePage(String title, IconData icon, String message) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center)])));

  Widget _morePage() => ListView(padding: const EdgeInsets.all(18), children: [
    Text('امکانات دارما', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    for (final item in [('تعاریف و حساب‌ها', Icons.account_tree_outlined), ('اشخاص', Icons.people_outline), ('وام‌ها و تسهیلات', Icons.handshake_outlined), ('خریدهای اعتباری', Icons.credit_card), ('بودجه‌بندی', Icons.pie_chart_outline), ('اهداف مالی', Icons.flag_outlined), ('تقویم مالی', Icons.calendar_month_outlined), ('تنظیمات', Icons.settings_outlined)])
      Card(child: ListTile(leading: Icon(item.$2), title: Text(item.$1), trailing: const Icon(Icons.chevron_left), onTap: () => item.$1 == 'تنظیمات' ? _showThemes() : _notice('بخش ${item.$1} در برنامه توسعه قرار دارد.'))),
  ]);

  void _showThemes() => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Padding(padding: EdgeInsets.all(16), child: Text('انتخاب پوسته', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
    for (final name in _themes.keys) ListTile(leading: CircleAvatar(backgroundColor: _themes[name]), title: Text(name), trailing: widget.themeName == name ? const Icon(Icons.check_circle) : null, onTap: () { widget.onThemeChanged(name); Navigator.pop(context); }),
    const SizedBox(height: 12),
  ]))));

  Future<void> _newTransaction({String? kind}) async {
    String selected = kind ?? 'expense';
    final title = TextEditingController();
    final amount = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Directionality(textDirection: TextDirection.rtl, child: Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('تراکنش جدید', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'income', label: Text('دریافت'), icon: Icon(Icons.south_west)), ButtonSegment(value: 'expense', label: Text('پرداخت'), icon: Icon(Icons.north_east))], selected: {selected}, onSelectionChanged: (v) => setSheet(() => selected = v.first)),
        const SizedBox(height: 14),
        TextFormField(controller: title, decoration: const InputDecoration(labelText: 'شرح تراکنش', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().isEmpty) ? 'شرح را وارد کنید' : null),
        const SizedBox(height: 12),
        TextFormField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ به ریال', border: OutlineInputBorder()), validator: (v) => int.tryParse((v ?? '').replaceAll(',', '')) == null || int.parse(v!.replaceAll(',', '')) <= 0 ? 'مبلغ معتبر وارد کنید' : null),
        const SizedBox(height: 18),
        FilledButton(onPressed: () async {
          if (!formKey.currentState!.validate()) return;
          await DarmaDatabase.instance.addSimpleTransaction(title: title.text.trim(), amount: int.parse(amount.text.replaceAll(',', '')), kind: selected);
          if (ctx.mounted) Navigator.pop(ctx, true);
        }, child: const Text('ثبت تراکنش')),
      ])),
    ))));
    title.dispose(); amount.dispose();
    if (result == true) await _refresh();
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))));
}
