import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../data.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/geo.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';
import 'passenger_screens.dart';

/// طلب سفر بين المدن: المدينة، الموعد، عدد المقاعد، والسعر.
class IntercityScreen extends StatefulWidget {
  const IntercityScreen({super.key});
  @override
  State<IntercityScreen> createState() => _IntercityScreenState();
}

class _IntercityScreenState extends State<IntercityScreen> {
  String _from = 'طرابلس';
  String _to = 'مصراتة';
  final _pickupNote = TextEditingController();
  final _comment = TextEditingController();
  DateTime _when = DateTime.now().add(const Duration(hours: 2));
  int _seats = 1;
  String _payment = 'cash';
  bool _fullCar = false;
  RouteInfo? _route;
  int? _price;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _calc();
  }

  Map<String, dynamic> get _details => {'full_car': _fullCar, 'from_city': _from, 'to_city': _to};

  int? get _suggested =>
      _route == null ? null : Pricing.suggest(Service.intercity, _route!.km, details: _details, seats: _seats);

  Future<void> _calc() async {
    if (_from == _to) {
      setState(() => _route = null);
      return;
    }
    setState(() => _route = null);
    final r = await Geo.route(libyanCities[_from]!, libyanCities[_to]!);
    if (!mounted) return;
    setState(() {
      _route = r;
      _price = _suggested;
    });
  }

  Future<void> _request() async {
    if (_route == null || _price == null) return;
    setState(() => _busy = true);
    try {
      final note = _pickupNote.text.trim();
      final id = await Api.createRide(
        pickup: Place(libyanCities[_from]!, note.isEmpty ? _from : '$_from · $note'),
        dropoff: Place(libyanCities[_to]!, _to),
        route: _route!,
        price: _price!.toDouble(),
        service: Service.intercity,
        details: _details,
        scheduledAt: _when,
        seats: _fullCar ? 4 : _seats,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        paymentMethod: _payment,
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OffersScreen(rideId: id)));
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _cityPicker(String label, String value, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [for (final c in libyanCities.keys) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) {
          if (v == null) return;
          onChanged(v);
          _calc();
        },
      );

  @override
  Widget build(BuildContext context) {
    final suggested = _suggested;
    return Scaffold(
      appBar: AppBar(title: const Text('سفر بين المدن')),
      backgroundColor: Colors.white,
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: _cityPicker('من', _from, (v) => setState(() => _from = v))),
          IconButton(
            tooltip: 'بدّل',
            onPressed: () {
              setState(() {
                final t = _from;
                _from = _to;
                _to = t;
              });
              _calc();
            },
            icon: const Icon(Icons.swap_horiz),
          ),
          Expanded(child: _cityPicker('إلى', _to, (v) => setState(() => _to = v))),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _pickupNote,
          decoration: const InputDecoration(labelText: 'مكان الركوب داخل المدينة (الحي أو أقرب معلم)'),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: const Text('موعد السفر'),
          subtitle: Text(fmtDate(_when)),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final d = await pickDateTime(context, initial: _when, minAhead: const Duration(minutes: 30));
            if (d != null) setState(() => _when = d);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('نبي السيارة كاملة'),
          subtitle: const Text('بدون ركاب آخرين'),
          value: _fullCar,
          onChanged: (v) => setState(() {
            _fullCar = v;
            _price = _suggested;
          }),
        ),
        if (!_fullCar)
          Row(children: [
            const Text('عدد المقاعد'),
            const Spacer(),
            IconButton(
              tooltip: 'أقل',
              onPressed: _seats <= 1
                  ? null
                  : () => setState(() {
                        _seats--;
                        _price = _suggested;
                      }),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_seats', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            IconButton(
              tooltip: 'أكثر',
              onPressed: _seats >= 6
                  ? null
                  : () => setState(() {
                        _seats++;
                        _price = _suggested;
                      }),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ]),
        const Divider(height: 28),
        if (_from == _to)
          const Text('اختار مدينتين مختلفتين', textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger))
        else if (_route == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Text('${_route!.km.toStringAsFixed(0)} كم · حوالي ${(_route!.minutes / 60).toStringAsFixed(1)} ساعة · السعر المقترح $suggested د.ل',
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mute)),
          const SizedBox(height: 8),
          const Text('اقترح سعرك', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
              onPressed: () => setState(() => _price = max(AppConfig.minFare.toInt(), _price! - 5)),
              child: const Text('−5'),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Money(_price!, size: 40)),
            OutlinedButton(onPressed: () => setState(() => _price = _price! + 5), child: const Text('+5')),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _comment, decoration: const InputDecoration(labelText: 'ملاحظة للسواق (شنط، أطفال…)')),
          const SizedBox(height: 12),
          PaymentPicker(value: _payment, onChanged: (v) => setState(() => _payment = v)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _request, child: Text('اطلب بـ $_price د.ل')),
        ],
      ]),
    );
  }
}
