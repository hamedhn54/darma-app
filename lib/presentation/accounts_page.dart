import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/darma_database.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  List<Map<String, Object?>> _accounts = [];
  bool _loading = true;
  final _money = NumberFormat('#,###', 'en_US');
  static const _types = <String, String>{
    'asset': 'دارایی‌ها',
    'liability': 'بدهی‌ها',
    'income': 'درآمدها',
    'expense': 'هزینه‌ها',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DarmaDatabase.instance.getAccountSummaries();
    if (!mounted) return;
    setState(() {
      _accounts = rows;
      _loading = false;
    });
  }

  String _digits(String value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(latin[i], persian[i]);
    }
    return value;
  }

  Future<void> _addAccount() async {
    final name = TextEditingController();
    String type = 'asset';
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('حساب جدید'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'سرفصل اصلی'),
                  items: _types.entries.map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'نام حساب',
                    hintText: 'مثلاً حساب بانک ملت',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'نام حساب را وارد کنید'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await DarmaDatabase.instance.createAccount(
                    name: name.text,
                    type: type,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
                  );
                }
              },
              child: const Text('ذخیره حساب'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (created == true) await _load();
  }

  Future<void> _rename(Map<String, Object?> account) async {
    final controller = TextEditingController(text: account['name'] as String);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ویرایش نام حساب'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام حساب'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await DarmaDatabase.instance.renameAccount(id: account['id'] as int, name: name);
      await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  Future<void> _delete(Map<String, Object?> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف حساب'),
        content: Text('حساب «${account['name']}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DarmaDatabase.instance.deleteAccount(account['id'] as int);
      await _load();
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعاریف و حساب‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        icon: const Icon(Icons.add),
        label: const Text('حساب جدید'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  const Text(
                    'حساب‌های شما در چهار سرفصل اصلی دسته‌بندی می‌شوند. حساب‌های سیستمی قابل حذف نیستند.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  for (final type in _types.keys) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        _types[type]!,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ..._accounts.where((account) => account['type'] == type).map((account) {
                      final balance = (account['balance'] as num?)?.toInt() ?? 0;
                      final system = account['is_system'] == 1;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(system ? Icons.account_balance_wallet_outlined : Icons.account_balance_outlined),
                          ),
                          title: Text(account['name'] as String),
                          subtitle: Text('${_digits(_money.format(balance.abs()))} ریال'),
                          trailing: system
                              ? const Icon(Icons.lock_outline, size: 19)
                              : PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'edit') _rename(account);
                                    if (action == 'delete') _delete(account);
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'edit', child: Text('ویرایش نام')),
                                    PopupMenuItem(value: 'delete', child: Text('حذف حساب')),
                                  ],
                                ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}
