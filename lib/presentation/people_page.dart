import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/darma_database.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final _money = NumberFormat('#,###', 'en_US');
  final _search = TextEditingController();
  List<Map<String, Object?>> _people = [];
  bool _loading = true;
  bool _includeInactive = false;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await DarmaDatabase.instance
        .getPeople(includeInactive: _includeInactive);
    if (!mounted) return;
    setState(() {
      _people = rows;
      _loading = false;
    });
  }

  String _amount(Object? value) =>
      _money.format((value as num?)?.toInt() ?? 0);

  Future<void> _editPerson({Map<String, Object?>? person}) async {
    final name = TextEditingController(
        text: person?['full_name'] as String? ?? '');
    final phone =
        TextEditingController(text: person?['phone'] as String? ?? '');
    final note = TextEditingController(text: person?['note'] as String? ?? '');
    final key = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(person == null ? 'افزودن شخص' : 'ویرایش شخص'),
          content: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'نام و نام خانوادگی',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'نام شخص را وارد کنید'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'شماره تماس (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: note,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'یادداشت (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                if (!key.currentState!.validate()) return;
                try {
                  if (person == null) {
                    await DarmaDatabase.instance.createPerson(
                      fullName: name.text,
                      phone: phone.text,
                      note: note.text,
                    );
                  } else {
                    await DarmaDatabase.instance.updatePerson(
                      personId: person['id'] as int,
                      fullName: name.text,
                      phone: phone.text,
                      note: note.text,
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    note.dispose();
    if (result == true) await _load();
  }

  Future<void> _toggleActive(Map<String, Object?> person) async {
    final active = (person['is_active'] as num).toInt() == 1;
    await DarmaDatabase.instance.setPersonActive(
      personId: person['id'] as int,
      isActive: !active,
    );
    await _load();
  }

  Future<void> _deletePerson(Map<String, Object?> person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف شخص'),
          content: Text(
              '«${person['full_name']}» حذف شود؟ این عملیات فقط برای اشخاص بدون سابقه مالی مجاز است.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await DarmaDatabase.instance.deletePerson(person['id'] as int);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _showLedger(Map<String, Object?> person) async {
    final rows = await DarmaDatabase.instance
        .getPersonLedger(person['id'] as int);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('گردش حساب ${person['full_name']}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('هنوز گردش مالی برای این شخص ثبت نشده است.'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final debit = (row['debit'] as num).toInt();
                          final credit = (row['credit'] as num).toInt();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['title'] as String? ?? ''),
                            subtitle: Text(
                                '${row['account_name']} • ${row['created_at']}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  debit > 0
                                      ? 'بدهکار: ${_amount(debit)}'
                                      : 'بستانکار: ${_amount(credit)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: debit > 0
                                        ? Colors.teal
                                        : Colors.deepOrange,
                                  ),
                                ),
                                const Text('ریال',
                                    style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _people.where((person) {
      final name = (person['full_name'] as String).toLowerCase();
      final phone = (person['phone'] as String? ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اشخاص و طرف‌حساب‌ها'),
          actions: [
            IconButton(
              tooltip: 'افزودن شخص',
              onPressed: () => _editPerson(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withValues(alpha: .18),
                      scheme.surfaceContainerHighest,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('مدیریت اشخاص حقیقی',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      'اطلاعات تماس و مانده حساب هر شخص در یک فهرست مستقل نگهداری می‌شود.',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'جست‌وجوی نام یا شماره تماس',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('نمایش اشخاص غیرفعال'),
                value: _includeInactive,
                onChanged: (value) async {
                  setState(() {
                    _includeInactive = value;
                    _loading = true;
                  });
                  await _load();
                },
              ),
              const SizedBox(height: 4),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 46, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 10),
                      const Text('شخصی ثبت نشده است'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _editPerson(),
                        icon: const Icon(Icons.add),
                        label: const Text('افزودن اولین شخص'),
                      ),
                    ],
                  ),
                )
              else
                for (final person in visible) _personCard(person),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editPerson(),
          icon: const Icon(Icons.add),
          label: const Text('شخص جدید'),
        ),
      ),
    );
  }

  Widget _personCard(Map<String, Object?> person) {
    final scheme = Theme.of(context).colorScheme;
    final active = (person['is_active'] as num).toInt() == 1;
    final net = (person['net_balance'] as num?)?.toInt() ?? 0;
    final color = net > 0
        ? Colors.teal
        : net < 0
            ? Colors.deepOrange
            : scheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showLedger(person),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: .12),
                    child: Icon(Icons.person_outline_rounded,
                        color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person['full_name'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 14)),
                        if ((person['phone'] as String? ?? '').isNotEmpty)
                          Text(person['phone'] as String,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _editPerson(person: person);
                      if (value == 'toggle') _toggleActive(person);
                      if (value == 'delete') _deletePerson(person);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit', child: Text('ویرایش')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(active ? 'غیرفعال‌سازی' : 'فعال‌سازی'),
                      ),
                      if (net == 0)
                        const PopupMenuItem(
                            value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ],
              ),
              const Divider(height: 22),
              Row(
                children: [
                  const Text('مانده حساب',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    net > 0
                        ? 'طلب از شخص'
                        : net < 0
                            ? 'بدهی به شخص'
                            : 'بدون مانده',
                    style: TextStyle(
                        color: color, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Text('${_amount(net.abs())} ریال',
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w900)),
                ],
              ),
              if (!active)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text('غیرفعال',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
