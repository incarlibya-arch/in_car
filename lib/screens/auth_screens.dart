import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'docs_screen.dart';
import 'wallet_screens.dart';

/// 1) إدخال رقم الهاتف
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    final digits = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) return showMsg(context, 'اكتب رقم هاتف ليبي صحيح، مثل 912345678');
    final phone = Api.normalizePhone(digits);
    setState(() => _busy = true);
    try {
      await Api.sendOtp(phone);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: phone)));
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.location_on_outlined, color: AppColors.ink),
              ),
              const SizedBox(width: 10),
              const Text('in car', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(24)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مشوارك بسعرك',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
                SizedBox(height: 6),
                Text('اقترح السعر اللي يناسبك، والسواق يقبل أو يعرض سعره.',
                    style: TextStyle(fontSize: 15, color: Color(0xFFC9D2E0), height: 1.6)),
              ]),
            ),
            const SizedBox(height: 28),
            const Text('رقم الهاتف', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(prefixText: '+218  ', hintText: '91 234 5678'),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('بنبعتولك رمز تحقق في رسالة نصية.', style: TextStyle(color: AppColors.mute, fontSize: 13)),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator()) : const Text('كمّل'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2) رمز التحقق
class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _verify() async {
    if (_ctrl.text.trim().length < 6) return showMsg(context, 'الرمز 6 أرقام');
    setState(() => _busy = true);
    try {
      await Api.verifyOtp(widget.phone, _ctrl.text.trim());
      if (mounted) restartToGate(context);
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رمز التحقق')),
      backgroundColor: Colors.white,
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('بعتنالك رمز من 6 أرقام على الرقم', style: const TextStyle(color: AppColors.mute)),
        Text(widget.phone, textDirection: TextDirection.ltr, textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : _verify, child: const Text('تأكيد')),
        TextButton(
          onPressed: _busy ? null : () => Api.sendOtp(widget.phone).then((_) => showMsg(context, 'تم إرسال رمز جديد')),
          child: const Text('ما وصلنيش الرمز، عاود ابعته'),
        ),
      ]),
    );
  }
}

/// 3) إكمال الملف: الاسم والدور وبيانات السيارة
class ProfileSetupScreen extends StatefulWidget {
  final Profile? existing;
  const ProfileSetupScreen({super.key, this.existing});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final _name = TextEditingController(text: widget.existing?.fullName);
  late final _car = TextEditingController(text: widget.existing?.carModel);
  late final _color = TextEditingController(text: widget.existing?.carColor);
  late final _plate = TextEditingController(text: widget.existing?.plate);
  late String _role = widget.existing?.role ?? 'passenger';
  late final Set<Service> _services = {...?widget.existing?.services};
  late String _vehicle = widget.existing?.vehicleType ?? 'car';
  late final Set<String> _pay = {'cash', ...?widget.existing?.paymentMethods};
  final Map<String, TextEditingController> _payDetails = {
    for (final k in ['bank_transfer', 'sadad', 'mobicash', 'other']) k: TextEditingController(),
  };
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showMsg(context, 'اكتب اسمك');
    if (_role == 'driver' && (_car.text.trim().isEmpty || _plate.text.trim().isEmpty)) {
      return showMsg(context, 'اكتب نوع السيارة ورقم اللوحة');
    }
    setState(() => _busy = true);
    try {
      await Api.saveProfile(
        fullName: _name.text.trim(),
        role: _role,
        carModel: _role == 'driver' ? _car.text.trim() : null,
        carColor: _role == 'driver' ? _color.text.trim() : null,
        plate: _role == 'driver' ? _plate.text.trim() : null,
        services: _role == 'driver' ? (_services.isEmpty ? [Service.city] : _services.toList()) : const [Service.city],
        vehicleType: _role == 'driver' ? _vehicle : 'car',
        paymentMethods: _role == 'driver' ? _pay.toList() : const ['cash'],
      );
      if (_role == 'driver') {
        await Api.savePaymentDetails({
          for (final k in _pay)
            if (k != 'cash') k: _payDetails[k]!.text,
        });
      }
      if (mounted) restartToGate(context);
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _roleBtn(String value, String title, String sub, IconData icon) {
    final sel = _role == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _role = value),
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            color: sel ? AppColors.accentSoft : Colors.white,
            border: Border.all(color: sel ? AppColors.ink : AppColors.line, width: sel ? 2 : 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 28),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
          ]),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (_services.isEmpty) _services.add(Service.city);
    if (widget.existing?.isDriver == true) {
      Api.myPaymentDetails().then((m) {
        if (!mounted) return;
        setState(() => m.forEach((k, v) => _payDetails[k]?.text = v));
      }).catchError((_) {});
    }
  }

  static const _payHints = {
    'bank_transfer': 'اسم المصرف ورقم الحساب',
    'sadad': 'رقم الهاتف المسجل في سداد',
    'mobicash': 'رقم الهاتف المسجل في موبي كاش',
    'other': 'اسم الطريقة والرقم',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'أهلاً بيك' : 'حسابي')),
      backgroundColor: Colors.white,
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          _roleBtn('passenger', 'راكب', 'أطلب مشوار', Icons.person_outline),
          const SizedBox(width: 10),
          _roleBtn('driver', 'سواق', 'استقبل الطلبات', Icons.directions_car_outlined),
        ]),
        const SizedBox(height: 20),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
        if (_role == 'driver') ...[
          const SizedBox(height: 12),
          TextField(controller: _car, decoration: const InputDecoration(labelText: 'نوع السيارة (مثلاً هيونداي أكسنت)')),
          const SizedBox(height: 12),
          TextField(controller: _color, decoration: const InputDecoration(labelText: 'اللون')),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(controller: _plate, decoration: const InputDecoration(labelText: 'رقم اللوحة', hintText: '5-123456')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            decoration: const InputDecoration(labelText: 'نوع المركبة'),
            items: [for (final e in vehicleTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _vehicle = v ?? 'car'),
          ),
          const SizedBox(height: 16),
          const Text('الخدمات اللي تقدمها', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in Service.values)
              FilterChip(
                label: Text(s.label),
                selected: _services.contains(s),
                onSelected: (v) => setState(() => v ? _services.add(s) : _services.remove(s)),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('طرق الدفع اللي تقبلها', style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('الفلوس توصلك مباشرة من الراكب. بياناتك ما تظهرش للراكب إلا بعد ما تبدا الرحلة.',
              style: TextStyle(fontSize: 12, color: AppColors.mute)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final e in paymentMethods.entries)
              FilterChip(
                label: Text(e.value),
                selected: _pay.contains(e.key),
                onSelected: e.key == 'cash' ? null : (v) => setState(() => v ? _pay.add(e.key) : _pay.remove(e.key)),
              ),
          ]),
          for (final k in _payDetails.keys)
            if (_pay.contains(k))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  controller: _payDetails[k],
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: '${paymentLabel(k)}: ${_payHints[k]}',
                    counterText: '',
                  ),
                ),
              ),
          if (widget.existing != null && widget.existing!.isDriver) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => DriverDocsScreen(me: widget.existing!))),
              icon: Icon(widget.existing!.isApproved ? Icons.verified : Icons.upload_file),
              label: Text(widget.existing!.isApproved ? 'الوثائق (حسابك موثّق)' : 'ارفع وثائق التوثيق'),
            ),
          ],
          const SizedBox(height: 8),
          const Text('لو غيّرت بيانات السيارة أو اللوحة، حسابك يرجع للمراجعة.',
              style: TextStyle(fontSize: 12, color: AppColors.mute)),
        ],
        const SizedBox(height: 28),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
        if (widget.existing?.isDriver == true)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverWalletScreen())),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('المحفظة'),
          ),
        if (widget.existing != null)
          FutureBuilder<bool>(
            future: Api.isAdmin(),
            builder: (context, a) => a.data == true
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('لوحة الإدارة'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              await Api.signOut();
              if (context.mounted) restartToGate(context);
            },
            child: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.danger)),
          ),
      ]),
    );
  }
}
