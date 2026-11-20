import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets.dart';

String _date(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// محفظة السائق: الرصيد، طلب شحن، وسجل الحركات.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});
  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  final Stream<double> _balance = Api.watchMyBalance();
  final Stream<AppSettings> _settings = Api.watchSettings();
  final Stream<List<TopupRequest>> _topups = Api.watchMyTopups();
  late Future<List<WalletTx>> _txs = Api.myTransactions();

  Future<void> _requestTopup(AppSettings s) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TopupSheet(info: s.topupInfo),
    );
    if (sent == true && mounted) showMsg(context, 'وصل طلبك، بيتشحن رصيدك بعد ما الإدارة تأكد الدفع');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحفظة')),
      body: StreamBuilder<AppSettings>(
        stream: _settings,
        builder: (context, ss) {
          final s = ss.data ?? const AppSettings();
          return RefreshIndicator(
            onRefresh: () async => setState(() => _txs = Api.myTransactions()),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              StreamBuilder<double>(
                stream: _balance,
                builder: (context, bs) {
                  final b = bs.data ?? 0;
                  final ok = s.canWork(b);
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(24)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('رصيدك', style: TextStyle(color: Color(0xFFC9D2E0))),
                      DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.white),
                        child: Money(b, size: 40),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ok ? 'تقدر تستقبل الطلبات' : 'رصيدك أقل من الحد الأدنى (${s.minBalance.toStringAsFixed(0)} د.ل). اشحن باش ترجع تستقبل طلبات.',
                        style: TextStyle(color: ok ? const Color(0xFF7CF0B8) : const Color(0xFFFFB4A8)),
                      ),
                    ]),
                  );
                },
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    s.isFreePeriod
                        ? 'بدون عمولة لين ${_date(s.freeUntil!)}، كل الأجرة لك.'
                        : s.commissionRate == 0
                            ? 'ما فيش عمولة حالياً، كل الأجرة لك.'
                            : 'عمولة in car ${s.ratePercent} من كل رحلة، وتنخصم من رصيدك تلقائياً بعد ما تنهي الرحلة.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _requestTopup(s),
                icon: const Icon(Icons.add_card),
                label: const Text('اشحن رصيدك'),
              ),
              const SizedBox(height: 20),
              StreamBuilder<List<TopupRequest>>(
                stream: _topups,
                builder: (context, ts) {
                  final list = ts.data ?? [];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('طلبات الشحن', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    for (final t in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${t.amount.toStringAsFixed(0)} د.ل · ${t.methodLabel}'),
                        subtitle: Text([_date(t.createdAt), if (t.adminNote != null) t.adminNote!].join(' · ')),
                        trailing: Text(t.statusLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: t.status == 'approved'
                                  ? AppColors.ok
                                  : t.status == 'rejected'
                                      ? AppColors.danger
                                      : AppColors.mute,
                            )),
                      ),
                    const Divider(),
                  ]);
                },
              ),
              const Text('سجل الحركات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              FutureBuilder<List<WalletTx>>(
                future: _txs,
                builder: (context, xs) {
                  if (!xs.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  if (xs.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('ما فيش حركات لين توا', textAlign: TextAlign.center, style: TextStyle(color: AppColors.mute)),
                    );
                  }
                  return Column(children: [
                    for (final t in xs.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.kindLabel),
                        subtitle: Text([_date(t.createdAt), if (t.note != null && t.note!.isNotEmpty) t.note!].join(' · ')),
                        trailing: Text(
                          '${t.amount > 0 ? '+' : ''}${t.amount.toStringAsFixed(2)} د.ل',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontWeight: FontWeight.w700, color: t.amount >= 0 ? AppColors.ok : AppColors.danger),
                        ),
                      ),
                  ]);
                },
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _TopupSheet extends StatefulWidget {
  final String info;
  const _TopupSheet({required this.info});
  @override
  State<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<_TopupSheet> {
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  String _method = 'cash_agent';
  bool _busy = false;

  Future<void> _send() async {
    final a = double.tryParse(_amount.text.trim());
    if (a == null || a <= 0) return showMsg(context, 'اكتب المبلغ');
    setState(() => _busy = true);
    try {
      await Api.requestTopup(a, _method, _ref.text.trim().isEmpty ? null : _ref.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('اشحن رصيدك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(widget.info, style: const TextStyle(color: AppColors.mute)),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'د.ل'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'طريقة الدفع'),
          items: [for (final e in topupMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _method = v ?? 'cash_agent'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ref,
          decoration: const InputDecoration(labelText: 'رقم العملية أو الإيصال (اختياري)'),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('إرسال الطلب')),
      ]),
    );
  }
}

/// لوحة الإدارة: العمولة، طلبات الشحن، وتعديل رصيد سائق.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final Stream<List<TopupRequest>> _pending = Api.watchPendingTopups();
  final _rate = TextEditingController();
  final _min = TextEditingController();
  final _freeDays = TextEditingController();
  final _info = TextEditingController();
  final _phone = TextEditingController();
  final _adjAmount = TextEditingController();
  final _adjNote = TextEditingController();
  final _emergency = TextEditingController();
  final _support = TextEditingController();
  bool _requireVerification = true;
  final Stream<List<SosAlert>> _sos = Api.watchOpenSos();
  late Future<List<Profile>> _pendingDrivers = Api.pendingDrivers();
  Profile? _found;
  double? _foundBalance;
  DateTime? _freeUntil;

  @override
  void initState() {
    super.initState();
    Api.settings().then((s) {
      if (!mounted) return;
      setState(() {
        _rate.text = (s.commissionRate * 100).toStringAsFixed(1);
        _min.text = s.minBalance.toStringAsFixed(0);
        _info.text = s.topupInfo;
        _freeUntil = s.freeUntil;
        _emergency.text = s.emergencyPhone;
        _support.text = s.supportPhone;
        _requireVerification = s.requireVerification;
      });
    });
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) showMsg(context, done);
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    }
  }

  Future<void> _saveSettings() async {
    final r = double.tryParse(_rate.text.trim()) ?? 0;
    final m = double.tryParse(_min.text.trim()) ?? 0;
    final days = int.tryParse(_freeDays.text.trim());
    final free = days == null ? _freeUntil : (days <= 0 ? null : DateTime.now().add(Duration(days: days)));
    if (r < 0 || r > 50) return showMsg(context, 'العمولة لازم تكون بين 0 و50%');
    await _run(
      () => Api.updateSettings(
        rate: r / 100,
        minBalance: m,
        freeUntil: free,
        topupInfo: _info.text.trim(),
        requireVerification: _requireVerification,
        emergencyPhone: _emergency.text.trim(),
        supportPhone: _support.text.trim(),
      ),
      'تم حفظ الإعدادات',
    );
    setState(() => _freeUntil = free);
  }

  Future<void> _findDriver() async {
    final p = await Api.findDriverByPhone(_phone.text);
    final b = p == null ? null : await Api.driverBalance(p.id);
    if (!mounted) return;
    setState(() {
      _found = p;
      _foundBalance = b;
    });
    if (p == null) showMsg(context, 'ما لقيتش سائق بهذا الرقم');
  }

  Future<void> _adjust() async {
    final a = double.tryParse(_adjAmount.text.trim());
    if (_found == null || a == null || a == 0) return showMsg(context, 'اكتب المبلغ (موجب للشحن، سالب للخصم)');
    await _run(() => Api.adjustWallet(_found!.id, a, _adjNote.text.trim().isEmpty ? 'من الإدارة' : _adjNote.text.trim()),
        'تم تعديل الرصيد');
    final b = await Api.driverBalance(_found!.id);
    if (mounted) setState(() => _foundBalance = b);
  }

  Widget _section(String title, List<Widget> children) => Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        StreamBuilder<List<SosAlert>>(
          stream: _sos,
          builder: (context, snap) {
            final list = snap.data ?? [];
            if (list.isEmpty) return const SizedBox.shrink();
            return Card(
              elevation: 0,
              color: const Color(0xFFFBE0DC),
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FutureBuilder(
                  future: Api.loadProfiles(list.map((a) => a.userId)),
                  builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('تنبيهات طوارئ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.danger)),
                    for (final a in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(Api.cached(a.userId)?.fullName ?? 'مستخدم'),
                        subtitle: Text(_date(a.createdAt)),
                        trailing: Wrap(spacing: 4, children: [
                          if (a.lat != null)
                            IconButton(
                              tooltip: 'الموقع',
                              icon: const Icon(Icons.map_outlined),
                              onPressed: () => launchUrl(Uri.parse('https://maps.google.com/?q=${a.lat},${a.lng}'),
                                  mode: LaunchMode.externalApplication),
                            ),
                          IconButton(
                            tooltip: 'اتصال',
                            icon: const Icon(Icons.call_outlined),
                            onPressed: () async {
                              final ph = await Api.partyPhone(a.userId);
                              if (ph != null) launchUrl(Uri.parse('tel:$ph'));
                            },
                          ),
                          IconButton(
                            tooltip: 'تمت المعالجة',
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () => _run(() => Api.resolveSos(a.id), 'تم'),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
            );
          },
        ),
        _section('سواقين ينتظروا التوثيق', [
          FutureBuilder<List<Profile>>(
            future: _pendingDrivers,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.isEmpty) return const Text('ما فيش سواقين جدد', style: TextStyle(color: AppColors.mute));
              return Column(children: [
                for (final d in snap.data!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Initial(d.fullName, size: 40),
                    title: Text(d.fullName),
                    subtitle: Text('${d.carLabel} · ${d.plate ?? ''} · ${d.vehicleLabel}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => DriverReviewScreen(driver: d)));
                      if (mounted) setState(() => _pendingDrivers = Api.pendingDrivers());
                    },
                  ),
              ]);
            },
          ),
        ]),
        _section('طلبات الشحن', [
          StreamBuilder<List<TopupRequest>>(
            stream: _pending,
            builder: (context, snap) {
              final list = snap.data ?? [];
              if (list.isEmpty) return const Text('ما فيش طلبات جديدة', style: TextStyle(color: AppColors.mute));
              return FutureBuilder(
                future: Api.loadProfiles(list.map((t) => t.driverId)),
                builder: (context, _) => Column(children: [
                  for (final t in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('${Api.cached(t.driverId)?.fullName ?? 'سائق'} · ${Api.cached(t.driverId)?.phone ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${t.amount.toStringAsFixed(0)} د.ل · ${t.methodLabel}'
                            '${t.reference != null ? ' · رقم العملية: ${t.reference}' : ''}'),
                        Text(_date(t.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                              onPressed: () => _run(() => Api.decideTopup(t.id, true), 'تم الشحن'),
                              child: const Text('تأكيد الشحن'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _run(() => Api.decideTopup(t.id, false, note: 'لم يتم تأكيد الدفع'), 'تم الرفض'),
                              child: const Text('رفض', style: TextStyle(color: AppColors.danger)),
                            ),
                          ),
                        ]),
                        const Divider(),
                      ]),
                    ),
                ]),
              );
            },
          ),
        ]),
        _section('الإعدادات والعمولة', [
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'نسبة العمولة', suffixText: '%'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _min,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'أقل رصيد باش السائق يستقبل طلبات', suffixText: 'د.ل'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _freeDays,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'فترة بدون عمولة (عدد الأيام من اليوم، 0 للإلغاء)',
              helperText: _freeUntil == null ? 'ما فيش فترة مجانية حالياً' : 'بدون عمولة لين ${_date(_freeUntil!)}',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _info,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'تعليمات الشحن اللي تظهر للسائق'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emergency,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم الطوارئ (يظهر في زر الطوارئ)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _support,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم خدمة العملاء'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('توثيق السواقين إجباري'),
            subtitle: const Text('السائق ما يقدرش يقدّم عروض لين توافق على وثائقه'),
            value: _requireVerification,
            onChanged: (v) => setState(() => _requireVerification = v),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _saveSettings, child: const Text('حفظ')),
        ]),
        _section('تعديل رصيد سائق', [
          Row(children: [
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(prefixText: '+218 ', hintText: '91 234 5678'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _findDriver, child: const Text('بحث')),
          ]),
          if (_found != null) ...[
            const SizedBox(height: 10),
            Text('${_found!.fullName} · ${_found!.carLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('الرصيد الحالي: ${_foundBalance?.toStringAsFixed(2) ?? '-'} د.ل'),
            const SizedBox(height: 10),
            TextField(
              controller: _adjAmount,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ (مثلاً 50 للشحن، -10 للخصم)', suffixText: 'د.ل'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _adjNote, decoration: const InputDecoration(labelText: 'ملاحظة')),
            const SizedBox(height: 12),
            FilledButton(onPressed: _adjust, child: const Text('تنفيذ')),
          ],
        ]),
      ]),
    );
  }
}

/// مراجعة وثائق سائق
class DriverReviewScreen extends StatefulWidget {
  final Profile driver;
  const DriverReviewScreen({super.key, required this.driver});
  @override
  State<DriverReviewScreen> createState() => _DriverReviewScreenState();
}

class _DriverReviewScreenState extends State<DriverReviewScreen> {
  late final Future<List<(DriverDoc, String)>> _docs = _load();
  final _note = TextEditingController();
  bool _busy = false;

  Future<List<(DriverDoc, String)>> _load() async {
    final docs = await Api.documentsOf(widget.driver.id);
    return [for (final d in docs) (d, await Api.documentUrl(d.path))];
  }

  Future<void> _decide(String status) async {
    if (status == 'rejected' && _note.text.trim().isEmpty) return showMsg(context, 'اكتب سبب الرفض');
    setState(() => _busy = true);
    try {
      await Api.setDriverStatus(widget.driver.id, status, note: _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    return Scaffold(
      appBar: AppBar(title: Text(d.fullName)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${d.carLabel} · لوحة ${d.plate ?? '-'} · ${d.vehicleLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('الخدمات: ${d.services.map((e) => e.label).join('، ')}'),
        const SizedBox(height: 12),
        FutureBuilder<List<(DriverDoc, String)>>(
          future: _docs,
          builder: (context, snap) {
            if (snap.hasError) return Text(friendlyError(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.isEmpty) return const Text('السائق ما رفعش وثائق لين توا', style: TextStyle(color: AppColors.danger));
            final missing = docTypes.keys.where((k) => !snap.data!.any((e) => e.$1.docType == k));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (missing.isNotEmpty)
                Text('ناقص: ${missing.map((k) => docTypes[k]).join('، ')}', style: const TextStyle(color: AppColors.danger)),
              for (final (doc, url) in snap.data!) ...[
                const SizedBox(height: 12),
                Text(docTypes[doc.docType] ?? doc.docType, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text('تعذر عرض الصورة')),
                ),
              ],
            ]);
          },
        ),
        const SizedBox(height: 16),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة للسائق (إجبارية عند الرفض)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton(onPressed: _busy ? null : () => _decide('approved'), child: const Text('توثيق'))),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _decide('rejected'),
              child: const Text('رفض', style: TextStyle(color: AppColors.danger)),
            ),
          ),
        ]),
      ]),
    );
  }
}
