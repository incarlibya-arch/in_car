import 'dart:async';
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../data.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/geo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth_screens.dart';
import 'common.dart';
import 'intercity_screen.dart';
import 'notifications_screen.dart';

/// الشاشة الرئيسية للراكب: اختيار الخدمة والوجهة واقتراح السعر.
class PassengerHome extends StatefulWidget {
  final Profile me;
  const PassengerHome({super.key, required this.me});
  @override
  State<PassengerHome> createState() => _PassengerHomeState();
}

class _PassengerHomeState extends State<PassengerHome> {
  final _map = MapController();
  final _comment = TextEditingController();
  final _item = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _cargo = TextEditingController();
  Service _service = Service.city;
  String _parcelSize = 'small';
  String _vehicle = 'pickup';
  int _helpers = 0;
  DateTime? _scheduledAt;
  String _payment = 'cash';
  Place? _from;
  Place? _to;
  RouteInfo? _route;
  int? _price;
  bool _pickingFrom = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    LatLng? here;
    try {
      here = await Geo.myLocation();
    } catch (_) {}
    final p = here ?? const LatLng(AppConfig.defaultLat, AppConfig.defaultLng);
    if (!mounted) return;
    setState(() => _from = Place(p, here == null ? 'ميدان الشهداء' : 'موقعك الحالي'));
    try {
      _map.move(p, 15);
    } catch (_) {}
    try {
      final open = await Api.myUnfinishedRide();
      if (open != null && mounted) _openRide(open.id, open.status == RideStatus.open);
    } catch (_) {}
  }

  Map<String, dynamic> get _details => switch (_service) {
        Service.courier => {
            'item': _item.text.trim(),
            'size': _parcelSize,
            if (_recipientName.text.trim().isNotEmpty) 'recipient_name': _recipientName.text.trim(),
            if (_recipientPhone.text.trim().isNotEmpty) 'recipient_phone': _recipientPhone.text.trim(),
          },
        Service.freight => {
            'vehicle': _vehicle,
            'helpers': _helpers,
            if (_cargo.text.trim().isNotEmpty) 'description': _cargo.text.trim(),
          },
        _ => <String, dynamic>{},
      };

  int? get _suggested => _route == null ? null : Pricing.suggest(_service, _route!.km, details: _details);

  void _resetPrice() {
    if (_route != null) setState(() => _price = _suggested);
  }

  void _openRide(String id, bool waiting) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => waiting ? OffersScreen(rideId: id) : PassengerTripScreen(rideId: id)),
    ).then((_) => setState(() {
          _to = null;
          _route = null;
          _price = null;
          _scheduledAt = null;
        }));
  }

  Future<void> _setPoint(Place place) async {
    setState(() {
      if (_pickingFrom) {
        _from = place;
      } else {
        _to = place;
      }
      _pickingFrom = false;
      _route = null;
    });
    if (_from != null && _to != null) {
      final r = await Geo.route(_from!.point, _to!.point);
      if (!mounted) return;
      setState(() => _route = r);
      _resetPrice();
      try {
        _map.fitCamera(CameraFit.coordinates(coordinates: r.points, padding: const EdgeInsets.all(60)));
      } catch (_) {}
    }
  }

  Future<void> _onMapTap(LatLng p) async {
    final label = await Geo.labelFor(p);
    await _setPoint(Place(p, label));
  }

  Future<void> _search({required bool from}) async {
    setState(() => _pickingFrom = from);
    final place = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PlaceSearchSheet(),
    );
    if (place != null) await _setPoint(place);
  }

  void _selectService(Service s) {
    if (s == Service.intercity) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const IntercityScreen()));
      return;
    }
    setState(() => _service = s);
    _resetPrice();
  }

  Future<void> _request() async {
    if (_from == null || _to == null || _route == null || _price == null) return;
    if (_service == Service.courier && _item.text.trim().isEmpty) return showMsg(context, 'اكتب شن الطرد');
    setState(() => _busy = true);
    try {
      final id = await Api.createRide(
        pickup: _from!,
        dropoff: _to!,
        route: _route!,
        price: _price!.toDouble(),
        service: _service,
        details: _details,
        scheduledAt: _scheduledAt,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        paymentMethod: _payment,
      );
      if (mounted) _openRide(id, true);
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _serviceFields() {
    switch (_service) {
      case Service.courier:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _item, decoration: const InputDecoration(labelText: 'شن الطرد؟', isDense: true)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final e in parcelSizes.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _parcelSize == e.key,
                onSelected: (_) {
                  setState(() => _parcelSize = e.key);
                  _resetPrice();
                },
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _recipientName, decoration: const InputDecoration(labelText: 'اسم المستلم', isDense: true)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _recipientPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم المستلم', isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]);
      case Service.freight:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            decoration: const InputDecoration(labelText: 'نوع المركبة', isDense: true),
            items: [
              for (final k in ['pickup', 'van', 'small_truck', 'large_truck'])
                DropdownMenuItem(value: k, child: Text(vehicleTypes[k]!)),
            ],
            onChanged: (v) {
              setState(() => _vehicle = v ?? 'pickup');
              _resetPrice();
            },
          ),
          const SizedBox(height: 8),
          TextField(controller: _cargo, decoration: const InputDecoration(labelText: 'شن البضاعة؟', isDense: true)),
          const SizedBox(height: 8),
          Row(children: [
            const Text('عمّال تحميل'),
            const Spacer(),
            IconButton(
              tooltip: 'أقل',
              onPressed: _helpers == 0
                  ? null
                  : () {
                      setState(() => _helpers--);
                      _resetPrice();
                    },
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_helpers', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            IconButton(
              tooltip: 'أكثر',
              onPressed: _helpers >= 4
                  ? null
                  : () {
                      setState(() => _helpers++);
                      _resetPrice();
                    },
              icon: const Icon(Icons.add_circle_outline),
            ),
          ]),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggested = _suggested;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: AppMap(
            controller: _map,
            pickup: _from?.point,
            dropoff: _to?.point,
            route: _route?.points ?? const [],
            onTap: _onMapTap,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _roundBtn(Icons.menu, 'حسابي', () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ProfileSetupScreen(existing: widget.me)))),
              const SizedBox(width: 8),
              _roundBtn(Icons.event_note_outlined, 'رحلاتي المحجوزة',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpcomingRidesScreen()))),
              const SizedBox(width: 8),
              const NotificationBell(),
              const Spacer(),
              if (_pickingFrom) const Chip(label: Text('اضغط على الخريطة لنقطة الانطلاق')),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .72),
            child: SingleChildScrollView(
              child: BottomSheetCard(children: [
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final s in Service.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          avatar: Icon(ServiceBadge.iconOf(s), size: 18),
                          label: Text(s.label),
                          selected: _service == s,
                          onSelected: (_) => _selectService(s),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                StopsBox(
                  from: _from?.label ?? 'نحددو في موقعك…',
                  to: _to?.label ?? 'وين ماشي؟ ابحث أو اضغط على الخريطة',
                  onTapFrom: () => _search(from: true),
                  onTapTo: () => _search(from: false),
                ),
                if (_route != null) ...[
                  const SizedBox(height: 10),
                  _serviceFields(),
                  Text('${_route!.km.toStringAsFixed(1)} كم · ${_route!.minutes} دقيقة · السعر المقترح $suggested د.ل',
                      textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mute, fontSize: 13)),
                  const SizedBox(height: 6),
                  const Text('اقترح سعرك', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _price = max(AppConfig.minFare.toInt(), _price! - 1)),
                      child: const Icon(Icons.remove),
                    ),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Money(_price!, size: 44)),
                    OutlinedButton(onPressed: () => setState(() => _price = _price! + 1), child: const Icon(Icons.add)),
                  ]),
                  if (_price! < suggested!)
                    const Text('سعر أقل من المقترح، ممكن ياخذ وقت أطول باش يقبله سواق',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.mute)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('الآن'), icon: Icon(Icons.bolt)),
                          ButtonSegment(value: true, label: Text('حجز لوقت'), icon: Icon(Icons.event)),
                        ],
                        selected: {_scheduledAt != null},
                        onSelectionChanged: (v) async {
                          if (v.first) {
                            final d = await pickDateTime(context, initial: _scheduledAt);
                            if (d != null) setState(() => _scheduledAt = d);
                          } else {
                            setState(() => _scheduledAt = null);
                          }
                        },
                      ),
                    ),
                  ]),
                  if (_scheduledAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('موعد الرحلة: ${fmtDate(_scheduledAt!)}',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _comment,
                    decoration: const InputDecoration(
                      hintText: 'ملاحظة للسواق (اختياري)',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  PaymentPicker(value: _payment, onChanged: (v) => setState(() => _payment = v)),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _busy ? null : _request,
                    child: Text(_scheduledAt == null ? 'اطلب بـ $_price د.ل' : 'احجز بـ $_price د.ل'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) => IconButton.filled(
        style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
        tooltip: tip,
        icon: Icon(icon),
        onPressed: onTap,
      );
}

/// بحث عن مكان
class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({super.key});
  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  List<Place> _results = [];
  Timer? _debounce;
  bool _loading = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () async {
      setState(() => _loading = true);
      final r = await Geo.search(q);
      if (mounted) {
        setState(() {
          _results = r;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'دوّر على مكان أو شارع'),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty && !_loading
                ? const Center(
                    child: Text('أو قفّل هذي الصفحة واضغط على الخريطة طول', style: TextStyle(color: AppColors.mute)))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(_results[i].label),
                      onTap: () => Navigator.pop(context, _results[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// عروض السواقين على طلب الراكب
class OffersScreen extends StatefulWidget {
  final String rideId;
  const OffersScreen({super.key, required this.rideId});
  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  late final Stream<Ride?> _ride = Api.watchRide(widget.rideId);
  late final Stream<List<Offer>> _offers = Api.watchOffers(widget.rideId);
  StreamSubscription<Ride?>? _sub;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _sub = _ride.listen((r) {
      if (_left || !mounted || r == null) return;
      if (r.isActive) {
        _left = true;
        if (r.isUpcoming) {
          showMsg(context, 'تم الحجز! السواق بيجيك في الموعد، وبيوصلك تذكير قبلها');
          Navigator.pop(context);
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PassengerTripScreen(rideId: r.id)));
        }
      } else if (r.status == RideStatus.cancelled) {
        _left = true;
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عروض السواقين'),
        leading: IconButton(
            tooltip: 'رجوع', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: StreamBuilder<Ride?>(
        stream: _ride,
        builder: (context, rs) {
          final ride = rs.data;
          if (ride == null) return const Center(child: CircularProgressIndicator());
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ServiceBadge(ride.service, scheduledAt: ride.scheduledAt),
                const SizedBox(height: 6),
                Text('طلبك بـ ${ride.offeredPrice.toStringAsFixed(0)} د.ل · ${ride.pickupLabel} ← ${ride.dropoffLabel}',
                    style: const TextStyle(color: AppColors.mute)),
                if (ride.detailsLine.isNotEmpty) Text(ride.detailsLine, style: const TextStyle(fontSize: 13)),
              ]),
            ),
            const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            Expanded(
              child: StreamBuilder<List<Offer>>(
                stream: _offers,
                builder: (context, os) {
                  final offers = os.data ?? [];
                  if (offers.isEmpty) {
                    return Center(
                      child: Text(
                        ride.scheduledAt != null
                            ? 'طلب الحجز وصل للسواقين، العروض بتظهر هنا.\nتقدر تقفّل الصفحة وترجعلها من «رحلاتي المحجوزة».'
                            : 'ندوّرولك على سواقين قريبين…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.mute),
                      ),
                    );
                  }
                  return FutureBuilder(
                    future: Api.loadProfiles(offers.map((o) => o.driverId)),
                    builder: (context, _) {
                      bool ok(Offer o) =>
                          ride.paymentMethod == 'cash' ||
                          (Api.cached(o.driverId)?.paymentMethods.contains(ride.paymentMethod) ?? false);
                      final sorted = [...offers.where(ok), ...offers.where((o) => !ok(o))];
                      return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _OfferCard(
                        offer: sorted[i],
                        rideMethod: ride.paymentMethod,
                        driver: Api.cached(sorted[i].driverId),
                        onAccept: () => _run(() => Api.acceptOffer(sorted[i].id)),
                        onDecline: () => _run(() => Api.declineOffer(sorted[i].id)),
                      ),
                    );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _run(() => Api.raisePrice(ride.id, ride.offeredPrice + 1)),
                    child: const Text('ارفع سعرك +1'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _run(() => Api.cancelOpenRide(ride.id)),
                    child: const Text('إلغاء الطلب', style: TextStyle(color: AppColors.danger)),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer offer;
  final Profile? driver;
  final String rideMethod;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _OfferCard({
    required this.offer,
    this.driver,
    required this.rideMethod,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final d = driver;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Initial(d?.fullName ?? ''),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(d?.fullName ?? 'سواق', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  if (d?.isApproved == true)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 4),
                      child: Icon(Icons.verified, size: 16, color: AppColors.ok),
                    ),
                ]),
                Text([d?.carLabel ?? '', if (d != null && d.vehicleType != 'car') d.vehicleLabel].where((e) => e.isNotEmpty).join(' · '),
                    style: const TextStyle(color: AppColors.mute, fontSize: 13)),
                Text(
                  '★ ${d?.rating.toStringAsFixed(1) ?? '-'} (${d?.ratingCount ?? 0})'
                  '${offer.etaMin != null ? ' · يوصل خلال ${offer.etaMin} د' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ]),
            ),
            Money(offer.price),
          ]),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final methods = d?.paymentMethods ?? const ['cash'];
            final ok = rideMethod == 'cash' || methods.contains(rideMethod);
            return Row(children: [
              Icon(ok ? Icons.check_circle : Icons.info_outline, size: 16, color: ok ? AppColors.ok : AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ok
                      ? 'يقبل: ${methods.map(paymentLabel).join(' · ')}'
                      : 'ما يقبلش ${paymentLabel(rideMethod)}، يقبل: ${methods.map(paymentLabel).join(' · ')}',
                  style: TextStyle(fontSize: 13, color: ok ? AppColors.ink : AppColors.danger),
                ),
              ),
            ]);
          }),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: onAccept,
                child: const Text('قبول'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: onDecline, child: const Text('رفض'))),
          ]),
        ]),
      ),
    );
  }
}

/// الرحلة بعد قبول السواق
class PassengerTripScreen extends StatefulWidget {
  final String rideId;
  const PassengerTripScreen({super.key, required this.rideId});
  @override
  State<PassengerTripScreen> createState() => _PassengerTripScreenState();
}

class _PassengerTripScreenState extends State<PassengerTripScreen> {
  late final Stream<Ride?> _ride = Api.watchRide(widget.rideId);
  Stream<Map<String, dynamic>?>? _carStream;
  String? _carDriver;
  int _stars = 0;

  String _title(Ride r) {
    if (r.status == RideStatus.accepted && r.isUpcoming) return 'رحلة محجوزة';
    return const {
          RideStatus.accepted: 'السواق جاي في الثنية',
          RideStatus.arrived: 'السواق وصل، اطلعله',
          RideStatus.started: 'ماشين لوجهتك',
          RideStatus.completed: 'وصلت بالسلامة',
          RideStatus.cancelled: 'انلغت الرحلة',
        }[r.status] ??
        '';
  }

  Future<void> _finish(Ride r) async {
    try {
      if (_stars > 0) await Api.rateRide(r.id, _stars);
    } catch (_) {}
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Ride?>(
      stream: _ride,
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (r.driverId != null && r.driverId != _carDriver) {
          _carDriver = r.driverId;
          _carStream = Api.watchDriverLocation(r.driverId!);
        }
        return Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: _carStream,
                builder: (context, cs) {
                  final c = cs.data;
                  final car = c == null ? null : LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
                  return AppMap(pickup: r.pickup, dropoff: r.dropoff, car: car, center: car ?? r.pickup);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
                  tooltip: 'رجوع',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FutureBuilder<Profile?>(
                future: r.driverId == null ? Future.value(null) : Api.profile(r.driverId!),
                builder: (context, ds) {
                  final d = ds.data;
                  return BottomSheetCard(children: [
                    ServiceBadge(r.service, scheduledAt: r.scheduledAt),
                    const SizedBox(height: 6),
                    Text(_title(r), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    Text('${r.pickupLabel} ← ${r.dropoffLabel}', style: const TextStyle(color: AppColors.mute)),
                    if (r.detailsLine.isNotEmpty) Text(r.detailsLine, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    if (d != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                        child: Row(children: [
                          Initial(d.fullName, size: 52),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(d.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                              Text('★ ${d.rating.toStringAsFixed(1)} · ${d.carLabel}',
                                  style: const TextStyle(fontSize: 13, color: AppColors.mute)),
                            ]),
                          ),
                          if (d.plate != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.ink, width: 2),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.white,
                              ),
                              child: Text(d.plate!,
                                  textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                        ]),
                      ),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('السعر المتفق عليه · ${paymentLabel(r.paymentMethod)}', style: const TextStyle(color: AppColors.mute)),
                      Money(r.finalPrice ?? r.offeredPrice),
                    ]),
                    const SizedBox(height: 12),
                    PaymentDetailsCard(ride: r),
                    if (r.isActive && d != null) TripActions(ride: r, otherUserId: d.id, otherName: d.fullName, driver: d),
                    if (r.status == RideStatus.completed) ...[
                      Text('قيّم ${d?.fullName ?? 'السواق'}',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          5,
                          (i) => IconButton(
                            tooltip: '${i + 1} نجوم',
                            iconSize: 36,
                            onPressed: () => setState(() => _stars = i + 1),
                            icon: Icon(i < _stars ? Icons.star : Icons.star_border, color: AppColors.accent),
                          ),
                        ),
                      ),
                      FilledButton(onPressed: () => _finish(r), child: Text(_stars > 0 ? 'ابعت التقييم' : 'تم')),
                    ],
                    if (r.status == RideStatus.cancelled)
                      FilledButton(onPressed: () => _finish(r), child: const Text('طلب جديد')),
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

/// الرحلات المحجوزة القادمة للراكب
class UpcomingRidesScreen extends StatefulWidget {
  const UpcomingRidesScreen({super.key});
  @override
  State<UpcomingRidesScreen> createState() => _UpcomingRidesScreenState();
}

class _UpcomingRidesScreenState extends State<UpcomingRidesScreen> {
  final Stream<List<Ride>> _rides = Api.watchMyUpcomingRides();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رحلاتي المحجوزة')),
      body: StreamBuilder<List<Ride>>(
        stream: _rides,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
                child: Text('ما عندكش رحلات محجوزة', style: TextStyle(color: AppColors.mute)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = list[i];
              return Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  title: Text('${r.pickupLabel} ← ${r.dropoffLabel}'),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),
                    ServiceBadge(r.service, scheduledAt: r.scheduledAt),
                    const SizedBox(height: 4),
                    Text(r.status == RideStatus.open ? 'ينتظر عروض السواقين' : 'تم الحجز مع سواق'),
                  ]),
                  trailing: Money(r.finalPrice ?? r.offeredPrice, size: 18),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          r.status == RideStatus.open ? OffersScreen(rideId: r.id) : PassengerTripScreen(rideId: r.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
