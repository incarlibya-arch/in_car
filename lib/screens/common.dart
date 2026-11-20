import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/geo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';

String fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// يختار تاريخ ووقت في المستقبل
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial, Duration minAhead = const Duration(minutes: 30)}) async {
  final now = DateTime.now();
  final first = now.add(minAhead);
  final init = initial != null && initial.isAfter(first) ? initial : first;
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(first.year, first.month, first.day),
    lastDate: now.add(const Duration(days: 30)),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
  if (t == null) return null;
  final r = DateTime(d.year, d.month, d.day, t.hour, t.minute);
  if (r.isBefore(first)) {
    if (context.mounted) showMsg(context, 'اختار وقت بعد ${minAhead.inMinutes} دقيقة على الأقل');
    return null;
  }
  return r;
}

/// شارة نوع الخدمة
class ServiceBadge extends StatelessWidget {
  final Service service;
  final DateTime? scheduledAt;
  const ServiceBadge(this.service, {super.key, this.scheduledAt});

  static IconData iconOf(Service s) => switch (s) {
        Service.city => Icons.directions_car_outlined,
        Service.intercity => Icons.route_outlined,
        Service.courier => Icons.inventory_2_outlined,
        Service.freight => Icons.local_shipping_outlined,
      };

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData i, String t, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 16),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        );
    return Wrap(spacing: 6, runSpacing: 4, children: [
      chip(iconOf(service), service.label, AppColors.surface),
      if (scheduledAt != null) chip(Icons.event_outlined, fmtDate(scheduledAt!), AppColors.accentSoft),
    ]);
  }
}

/// أزرار أثناء الرحلة: اتصال، محادثة، مشاركة، طوارئ
class TripActions extends StatelessWidget {
  final Ride ride;
  final String otherUserId;
  final String otherName;
  final Profile? driver;
  const TripActions({super.key, required this.ride, required this.otherUserId, required this.otherName, this.driver});

  Future<void> _call(BuildContext context) async {
    final phone = await Api.partyPhone(otherUserId);
    if (phone == null) {
      if (context.mounted) showMsg(context, 'الرقم يظهر بس أثناء الرحلة');
      return;
    }
    final ok = await launchUrl(Uri.parse('tel:$phone'));
    if (!ok && context.mounted) showMsg(context, 'الرقم: $phone');
  }

  Future<void> _share(BuildContext context) async {
    final here = await Geo.myLocation();
    final text = [
      'أنا في رحلة in car:',
      '${ride.pickupLabel} ← ${ride.dropoffLabel}',
      if (driver != null) 'السائق: ${driver!.fullName} · ${driver!.carLabel}${driver!.plate != null ? ' · لوحة ${driver!.plate}' : ''}',
      if (here != null) 'موقعي توا: https://maps.google.com/?q=${here.latitude},${here.longitude}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
    if (context.mounted) showMsg(context, ok ? 'اختار الشخص اللي تبي تشاركه' : 'تم نسخ تفاصيل الرحلة، الصقها في أي محادثة');
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, String t, VoidCallback f, {Color? color}) => Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), foregroundColor: color),
            onPressed: f,
            child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(i), Text(t, style: const TextStyle(fontSize: 12))]),
          ),
        );
    return Row(children: [
      btn(Icons.call_outlined, 'اتصال', () => _call(context)),
      const SizedBox(width: 6),
      btn(Icons.chat_bubble_outline, 'رسالة', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ChatScreen(rideId: ride.id, otherName: otherName)))),
      const SizedBox(width: 6),
      btn(Icons.share_outlined, 'مشاركة', () => _share(context)),
      const SizedBox(width: 6),
      btn(Icons.sos_outlined, 'طوارئ', () => showSosSheet(context, ride.id), color: AppColors.danger),
    ]);
  }
}

/// نافذة الطوارئ: تنبيه الإدارة + الاتصال برقم الطوارئ
Future<void> showSosSheet(BuildContext context, String? rideId) async {
  final s = await Api.settings();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('طوارئ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.danger)),
        const SizedBox(height: 6),
        const Text('لو حاسس بخطر، اطلب المساعدة توا. فريق in car بيوصله تنبيه فيه موقعك وتفاصيل الرحلة.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('نبّه فريق in car'),
          onPressed: () async {
            final here = await Geo.myLocation();
            try {
              await Api.sendSos(rideId: rideId, lat: here?.latitude, lng: here?.longitude);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showMsg(context, 'وصل التنبيه، فريقنا بيتواصل معاك');
              }
            } catch (e) {
              if (ctx.mounted) showMsg(context, friendlyError(e));
            }
          },
        ),
        if (s.emergencyPhone.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.call),
            label: Text('اتصل بالطوارئ ${s.emergencyPhone}'),
            onPressed: () => launchUrl(Uri.parse('tel:${s.emergencyPhone}')),
          ),
        ],
        if (s.supportPhone.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.support_agent),
            label: Text('خدمة العملاء ${s.supportPhone}'),
            onPressed: () => launchUrl(Uri.parse('tel:${s.supportPhone}')),
          ),
        ],
      ]),
    ),
  );
}
