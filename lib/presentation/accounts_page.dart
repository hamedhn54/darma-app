import 'package:flutter/material.dart';
import '../data/darma_database.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  static const _types = <String, String>{
    'asset': 'دارایی‌ها',
    'liability': 'بدهی‌ها',
    'income': 'درآمدها',
    'expense': 'هزینه‌ها',
  };

  static const _icons = <String, IconData>{
    'asset': Icons.account_balance_wallet_outlined,
    'liability': Icons.credit_card_outlined,
    'income': Icons.trending_up_rounded,
    'expense': Icons.trending_down_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعاریف')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'سرفصل موردنظر را انتخاب کنید تا حساب‌های معین و تفصیلی آن را مدیریت کنید.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final entry in _types.entries)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(_icons[entry.key]),
                ),
                title: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('مشاهده و مدیریت معین و تفصیلی'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AccountGroupPage(type: entry.key, title: entry.value),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AccountGroupPage extends StatefulWidget {
  const AccountGroupPage({super.key, required this.type, required this.title});
  final String type;
  final String title;

  @override
  State<AccountGroupPage> createState() => _AccountGroupPageState();
}

class _AccountGroupPageState extends State<AccountGroupPage> {
  List<Map<String, Object?>> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DarmaDatabase.instance.getAccountSummaries();
    if (!mounted) return;
    setState(() {
      _accounts = rows.where((a) => a['type'] == widget.type).toList();
      _loading = false;
    });
  }

  List<Map<String, Object?>> get _mainAccounts {
    return _accounts.where((a) => a['parent_id'] == a['root_id']).toList();
  }

  List<Map<String, Object?>> _detailsOf(int id) {
    return _accounts.where((a) => a['parent_id'] == id).toList();
  }

  String _errorText(Object error) =>
      error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _nameDialog({String? initial, required String title}) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'نام حساب'),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  Future<void> _addMain() async {
    final name = await _nameDialog(title: 'معین جدید');
    if (name == null) return;
    try {
      await DarmaDatabase.instance.createAccount(name: name, type: widget.type);
      await _load();
    } catch (error) {
      _message(_errorText(error));
    }
  }

  Future<void> _addDetail(int parentId) async {
    final name = await _nameDialog(title: 'تفصیلی جدید');
    if (name == null) return;
    try {
      await DarmaDatabase.instance.createAccount(
        name: name,
        type: widget.type,
        parentId: parentId,
      );
      await _load();
    } catch (error) {
      _message(_errorText(error));
    }
  }

  Future<void> _rename(Map<String, Object?> account) async {
    final name = await _nameDialog(
      initial: account['name'] as String,
      title: account['parent_id'] == account['root_id'] ? 'ویرایش معین' : 'ویرایش تفصیلی',
    );
    if (name == null) return;
    try {
      await DarmaDatabase.instance.renameAccount(id: account['id'] as int, name: name);
      await _load();
    } catch (error) {
      _message(_errorText(error));
    }
  }

  Future<void> _delete(Map<String, Object?> account) async {
    final isMain = account['parent_id'] == account['root_id'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isMain ? 'حذف حساب معین' : 'حذف حساب تفصیلی'),
        content: Text('«${account['name']}» حذف شود؟ اگر حساب گردش مالی یا زیرحساب داشته باشد، حذف نخواهد شد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DarmaDatabase.instance.deleteAccount(account['id'] as int);
      await _load();
    } catch (error) {
      _message(_errorText(error));
    }
  }

  Widget _menu(Map<String, Object?> account) {
    final locked = account['is_system'] == 1;
    return PopupMenuButton<String>(
      tooltip: 'مدیریت حساب',
      onSelected: (value) {
        if (value == 'rename') _rename(account);
        if (value == 'delete') _delete(account);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('ویرایش نام')),
        PopupMenuItem(
          value: 'delete',
          enabled: !locked,
          child: const Text('حذف'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(locked ? Icons.lock_outline : Icons.more_vert),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mains = _mainAccounts;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMain,
        icon: const Icon(Icons.add),
        label: const Text('معین جدید'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                children: [
                  Text('حساب‌های معین', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (mains.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('هنوز حساب معینی ثبت نشده است.')),
                    ),
                  for (final main in mains)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: PageStorageKey('account-${main['id']}'),
                        leading: const CircleAvatar(child: Icon(Icons.account_tree_outlined)),
                        title: Text(main['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${_detailsOf(main['id'] as int).length} تفصیلی'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'افزودن تفصیلی',
                              onPressed: () => _addDetail(main['id'] as int),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            _menu(main),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: [
                          for (final detail in _detailsOf(main['id'] as int))
                            ListTile(
                              contentPadding: const EdgeInsetsDirectional.only(start: 54, end: 12),
                              leading: const Icon(Icons.subdirectory_arrow_left_rounded, size: 20),
                              title: Text(detail['name'] as String),
                              trailing: _menu(detail),
                            ),
                          if (_detailsOf(main['id'] as int).isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: Text('برای این معین هنوز تفصیلی ثبت نشده است.'),
                            ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () => _addDetail(main['id'] as int),
                              icon: const Icon(Icons.add),
                              label: const Text('افزودن تفصیلی'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
