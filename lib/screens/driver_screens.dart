import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/geo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth_screens.dart';
import 'common.dart';
import 'docs_screen.dart';
import 'notifications_screen.dart';
import 'wallet_screens.dart';

/// الشاشة الرئيسية للسائق: الطلبات القريبة وتقديم العروض.
class DriverHome extends StatefulWidget {
  final Profile me;
  const DriverHome({super.key, required this.me});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool _online = false;
  LatLng? _here;
  Timer? _locTimer;
  StreamSubscription<List<Ride>>? _mine;
  final Stream<List<Ride>> _open = Api.watchOpenRides();
  final Stream<List<Offer>> _myOffers = Api.watchMyOffers();
  final Stream<double> _balance = Api.watchMyBalance();
  final Stream<AppSettings> _settings = Api.watchSettings();
  List<Ride> _upcoming = [];
  String? _activeShown;
  Service? _filter;

  @override
  void initState() {
    super.initState();
    _mine = Api.watchMyDriverRides().listen((rides) {
      if (!mounted) return;
      setState(() {
        _upcoming = rides.where((r) => r.status == RideStatus.accepted && r.isUpcoming).toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
      });
      final active = rides.where((r) => r.isActive && !(r.status == RideStatus.accepted && r.isUpcoming)).toList();
      if (active.isEmpty || _activeShown == active.first.id) return;
      _activeShown = active.first.id;
      Navigator.push(context, MaterialPageRoute(builder: (_) => DriverTripScreen(rideId: active.first.id)))
          .then((_) => _activeShown = null);
    });
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    _mine?.cancel();
    if (_online && _here != null) Api.updateMyLocation(_here!.latitude, _here!.longitude, false);
    super.dispose();
  }

  Future<void> _pushLocation() async {
    final p = await Geo.myLocation();
    if (p == null) {
      if (mounted) showMsg(context, 'فعّل خدمة الموقع باش توصلك الطلبات ويشوفك الراكب');
      return;
    }
    _here = p;
    try {
      await Api.updateMyLocation(p.latitude, p.longitude, _online);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggleOnline() async {
    setState(() => _online = !_online);
    _locTimer?.cancel();
    if (_online) {
      await _pushLocation();
      _locTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pushLocation());
    } else if (_here != null) {
      await Api.updateMyLocation(_here!.latitude, _here!.longitude, false);
    }
  }

  int _etaTo(Ride r) {
    if (_here == null) return 5;
    final km = const Distance().as(LengthUnit.Meter, _here!, r.pickup) / 1000 * 1.35;
    return (km / 30 * 60).round().clamp(1, 600);
  }

  String _distTo(Ride r) {
    if (_here == null || r.service == Service.intercity) return '';
    final km = const Distance().as(LengthUnit.Meter, _here!, r.pickup) / 1000;
    return ' · على بعد ${km.toStringAsFixed(1)} كم';
  }

  bool _fits(Ride r) {
    if (!widget.me.services.contains(r.service)) return false;
    if (_filter != null && r.service != _filter) return false;
    if (r.service == Service.intercity || _here == null) return true;
    // الطلبات داخل المدينة: في حدود 25 كم
    return const Distance().as(LengthUnit.Kilometer, _here!, r.pickup) <= 25;
  }

  Future<void> _offer(Ride r, double price) async {
    try {
      await Api.sendOffer(r.id, price, _etaTo(r));
      if (mounted) showMsg(context, 'تم إرسال عرضك بـ ${price.toStringAsFixed(0)} د.ل');
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    }
  }

  Future<void> _customOffer(Ride r) async {
    final ctrl = TextEditingController(text: (r.offeredPrice + 5).toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('اعرض سعرك'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: 'د.ل'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (v != null && v > 0) await _offer(r, v);
  }

  void _openWallet() => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverWalletScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مرحبا، ${widget.me.fullName}', style: const TextStyle(fontSize: 13, color: AppColors.mute)),
          const Text('الطلبات', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        actions: [
          StreamBuilder<double>(
            stream: _balance,
            builder: (context, bs) => TextButton.icon(
              onPressed: _openWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text('${(bs.data ?? 0).toStringAsFixed(0)} د.ل'),
            ),
          ),
          const NotificationBell(),
          IconButton(
            tooltip: 'حسابي',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ProfileSetupScreen(existing: widget.me))),
          ),
        ],
      ),
      body: Column(children: [
        _banners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 44),
                backgroundColor: _online ? AppColors.ok : AppColors.line,
                foregroundColor: _online ? Colors.white : AppColors.ink,
              ),
              onPressed: _toggleOnline,
              icon: Icon(_online ? Icons.circle : Icons.circle_outlined, size: 12),
              label: Text(_online ? 'متصل' : 'غير متصل'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(label: const Text('الكل'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                  ),
                  for (final s in widget.me.services)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        avatar: Icon(ServiceBadge.iconOf(s), size: 16),
                        label: Text(s.label),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        if (_upcoming.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Card(
              elevation: 0,
              color: AppColors.accentSoft,
              child: Column(children: [
                for (final r in _upcoming)
                  ListTile(
                    leading: const Icon(Icons.event_available),
                    title: Text('رحلة محجوزة · ${fmtDate(r.scheduledAt!)}'),
                    subtitle: Text('${r.pickupLabel} ← ${r.dropoffLabel}'),
                    trailing: Money(r.finalPrice ?? r.offeredPrice, size: 16),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverTripScreen(rideId: r.id))),
                  ),
              ]),
            ),
          ),
        Expanded(child: _feed()),
      ]),
    );
  }

  Widget _banners() {
    if (!widget.me.isApproved) {
      return StreamBuilder<AppSettings>(
        stream: _settings,
        builder: (context, ss) {
          if (ss.data?.requireVerification == false) return _walletBanner();
          return MaterialBanner(
            backgroundColor: AppColors.accentSoft,
            content: Text(widget.me.driverStatus == 'rejected'
                ? 'ما تمش قبول وثائقك. ارفعها من جديد باش تقدر تقدّم عروض.'
                : 'حسابك قيد المراجعة. ارفع وثائقك لو ما رفعتهاش، وبيوصلك إشعار أول ما يتوثق.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => DriverDocsScreen(me: widget.me))),
                child: const Text('الوثائق'),
              ),
            ],
          );
        },
      );
    }
    return _walletBanner();
  }

  Widget _walletBanner() => StreamBuilder<AppSettings>(
        stream: _settings,
        builder: (context, ss) => StreamBuilder<double>(
          stream: _balance,
          builder: (context, bs) {
            final st = ss.data;
            if (st == null || st.canWork(bs.data ?? 0)) return const SizedBox.shrink();
            return MaterialBanner(
              backgroundColor: AppColors.accentSoft,
              content: Text('رصيد محفظتك أقل من ${st.minBalance.toStringAsFixed(0)} د.ل، اشحن باش تقدر تقدّم عروض.'),
              actions: [TextButton(onPressed: _openWallet, child: const Text('اشحن'))],
            );
          },
        ),
      );

  Widget _feed() {
    if (!_online) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('أنت غير متصل. اضغط «غير متصل» باش تبدأ تستقبل الطلبات.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.mute, fontSize: 16)),
        ),
      );
    }
    return StreamBuilder<List<Offer>>(
      stream: _myOffers,
      builder: (context, os) {
        final mine = {for (final o in os.data ?? <Offer>[]) o.rideId: o};
        return StreamBuilder<List<Ride>>(
          stream: _open,
          builder: (context, rs) {
            if (rs.hasError) return Center(child: Text(friendlyError(rs.error!)));
            if (!rs.hasData) return const Center(child: CircularProgressIndicator());
            final rides = rs.data!.where(_fits).toList();
            if (rides.isEmpty) {
              return const Center(
                child: Text('ما فيش طلبات توا. أول ما راكب يطلب، بيظهر هنا.', style: TextStyle(color: AppColors.mute)),
              );
            }
            return FutureBuilder(
              future: Api.loadProfiles(rides.map((r) => r.passengerId)),
              builder: (context, _) => ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rides.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _RideRequestCard(
                  ride: rides[i],
                  passenger: Api.cached(rides[i].passengerId),
                  distance: _distTo(rides[i]),
                  myOffer: mine[rides[i].id],
                  onOffer: (p) => _offer(rides[i], p),
                  onCustom: () => _customOffer(rides[i]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RideRequestCard extends StatelessWidget {
  final Ride ride;
  final Profile? passenger;
  final String distance;
  final Offer? myOffer;
  final void Function(double) onOffer;
  final VoidCallback onCustom;
  const _RideRequestCard({
    required this.ride,
    this.passenger,
    required this.distance,
    this.myOffer,
    required this.onOffer,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final p = ride.offeredPrice;
    final pending = myOffer != null && myOffer!.status == 'pending';
    final declined = myOffer != null && myOffer!.status == 'declined';
    final steps = ride.service == Service.intercity || ride.service == Service.freight ? [5, 10, 20] : [2, 3, 5];
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ServiceBadge(ride.service, scheduledAt: ride.scheduledAt),
          const SizedBox(height: 10),
          Row(children: [
            Initial(passenger?.fullName ?? '', size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${passenger?.fullName ?? 'راكب'}${passenger != null && passenger!.ratingCount > 0 ? ' · ★ ${passenger!.rating.toStringAsFixed(1)}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('${ride.distanceKm.toStringAsFixed(1)} كم · ${ride.durationMin} د$distance',
                    style: const TextStyle(fontSize: 12, color: AppColors.mute)),
              ]),
            ),
            Money(p, size: 28),
          ]),
          const SizedBox(height: 10),
          StopsBox(from: ride.pickupLabel, to: ride.dropoffLabel),
          if (ride.detailsLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(ride.detailsLine, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          if (ride.comment != null) ...[
            const SizedBox(height: 6),
            Text('ملاحظة: ${ride.comment}', style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 12),
          if (pending)
            Text('عرضت ${myOffer!.price.toStringAsFixed(0)} د.ل · بانتظار رد الراكب',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mute))
          else ...[
            if (declined)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('الراكب رفض عرضك السابق، تقدر تعرض مرة ثانية',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.mute)),
              ),
            FilledButton(onPressed: () => onOffer(p), child: Text('قبول بـ ${p.toStringAsFixed(0)} د.ل')),
            const SizedBox(height: 8),
            const Text('أو اعرض سعرك', style: TextStyle(fontSize: 13, color: AppColors.mute)),
            const SizedBox(height: 6),
            Row(children: [
              for (final d in steps) ...[
                Expanded(
                  child: OutlinedButton(onPressed: () => onOffer(p + d), child: Text('${(p + d).toStringAsFixed(0)} د.ل')),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(child: OutlinedButton(onPressed: onCustom, child: const Text('سعر آخر'))),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// رحلة السائق بعد ما الراكب يقبل عرضه
class DriverTripScreen extends StatefulWidget {
  final String rideId;
  const DriverTripScreen({super.key, required this.rideId});
  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  late final Stream<Ride?> _ride = Api.watchRide(widget.rideId);
  bool _busy = false;

  Future<void> _advance(Ride r, RideStatus to) async {
    if (to == RideStatus.cancelled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إلغاء الرحلة؟'),
          content: const Text('الراكب بيوصله إشعار بالإلغاء.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الرحلة')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await Api.advanceRide(r.id, to);
      if (to == RideStatus.completed || to == RideStatus.cancelled) {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _navigate(LatLng to) => launchUrl(
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}&travelmode=driving'),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Ride?>(
      stream: _ride,
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final upcoming = r.status == RideStatus.accepted && r.isUpcoming;
        final step = switch (r.status) {
          RideStatus.accepted when upcoming => ('رحلة محجوزة · ${fmtDate(r.scheduledAt!)}', 'وصلت للراكب', RideStatus.arrived, r.pickup),
          RideStatus.accepted => ('روح للراكب', 'وصلت للراكب', RideStatus.arrived, r.pickup),
          RideStatus.arrived => ('أنت عند الراكب', 'بدء الرحلة', RideStatus.started, r.pickup),
          RideStatus.started => ('الرحلة جارية', 'إنهاء الرحلة', RideStatus.completed, r.dropoff),
          _ => ('انتهت الرحلة', 'رجوع', RideStatus.completed, r.dropoff),
        };
        return Scaffold(
          body: Stack(children: [
            Positioned.fill(child: AppMap(pickup: r.pickup, dropoff: r.dropoff, center: step.$4)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
                  tooltip: 'رجوع',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FutureBuilder<Profile?>(
                future: Api.profile(r.passengerId),
                builder: (context, ps) {
                  final pax = ps.data;
                  return BottomSheetCard(children: [
                    ServiceBadge(r.service, scheduledAt: r.scheduledAt),
                    const SizedBox(height: 6),
                    Text(step.$1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    Text('${pax?.fullName ?? 'راكب'} · ${r.pickupLabel} ← ${r.dropoffLabel}',
                        style: const TextStyle(color: AppColors.mute)),
                    if (r.detailsLine.isNotEmpty) Text(r.detailsLine, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (r.service == Service.courier && r.details['recipient_phone'] != null)
                      Text('رقم المستلم: ${r.details['recipient_phone']}', textDirection: TextDirection.rtl),
                    if (r.comment != null) Text('ملاحظة: ${r.comment}'),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('السعر · نقداً', style: TextStyle(color: AppColors.mute)),
                      Money(r.finalPrice ?? r.offeredPrice),
                    ]),
                    const SizedBox(height: 12),
                    if (r.isActive && pax != null) ...[
                      TripActions(ride: r, otherUserId: pax.id, otherName: pax.fullName),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _navigate(step.$4),
                        icon: const Icon(Icons.navigation_outlined),
                        label: Text(r.status == RideStatus.started ? 'الملاحة للوجهة' : 'الملاحة للراكب'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : r.isActive
                              ? () => _advance(r, step.$3)
                              : () => Navigator.pop(context),
                      child: Text(step.$2),
                    ),
                    if (r.status == RideStatus.accepted || r.status == RideStatus.arrived)
                      TextButton(
                        onPressed: _busy ? null : () => _advance(r, RideStatus.cancelled),
                        child: const Text('إلغاء الرحلة', style: TextStyle(color: AppColors.danger)),
                      ),
                  ]);
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}
