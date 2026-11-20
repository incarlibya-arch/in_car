import 'package:latlong2/latlong.dart';

import 'models.dart';

/// مدن ليبيا لخدمة السفر بين المدن (إحداثيات تقريبية لمركز كل مدينة)
const libyanCities = <String, LatLng>{
  'طرابلس': LatLng(32.8872, 13.1913),
  'بنغازي': LatLng(32.1167, 20.0667),
  'مصراتة': LatLng(32.3754, 15.0925),
  'الزاوية': LatLng(32.7571, 12.7276),
  'زليتن': LatLng(32.4674, 14.5687),
  'الخمس': LatLng(32.6486, 14.2619),
  'صبراتة': LatLng(32.7933, 12.4885),
  'زوارة': LatLng(32.9312, 12.0820),
  'غريان': LatLng(32.1722, 13.0203),
  'ترهونة': LatLng(32.4350, 13.6332),
  'بني وليد': LatLng(31.7566, 13.9942),
  'يفرن': LatLng(32.0629, 12.5286),
  'نالوت': LatLng(31.8685, 10.9812),
  'سرت': LatLng(31.2089, 16.5887),
  'أجدابيا': LatLng(30.7554, 20.2263),
  'المرج': LatLng(32.4925, 20.8306),
  'البيضاء': LatLng(32.7627, 21.7551),
  'درنة': LatLng(32.7648, 22.6391),
  'طبرق': LatLng(32.0836, 23.9764),
  'سبها': LatLng(27.0377, 14.4283),
  'هون': LatLng(29.1268, 15.9477),
  'الكفرة': LatLng(24.1997, 23.2905),
  'غات': LatLng(24.9647, 10.1728),
};

/// السعر المقترح لكل خدمة (أمثلة — عدّلها حسب السوق)
class Pricing {
  static const _cityBase = 4.0, _cityKm = 1.2, _min = 5.0;
  static const _courierExtra = 2.0;
  static const _intercitySeatKm = 0.12; // للمقعد الواحد لكل كم
  static const _freight = {
    'pickup': (20.0, 2.0),
    'small_truck': (40.0, 3.0),
    'large_truck': (80.0, 4.0),
    'van': (15.0, 1.6),
    'car': (10.0, 1.4),
  };

  static int suggest(Service s, double km, {Map<String, dynamic> details = const {}, int seats = 1}) {
    double p;
    switch (s) {
      case Service.city:
        p = _cityBase + _cityKm * km;
      case Service.courier:
        final sizeExtra = {'small': 0.0, 'medium': 2.0, 'large': 5.0}[details['size']] ?? 0.0;
        p = _cityBase + _courierExtra + sizeExtra + _cityKm * km;
      case Service.freight:
        final f = _freight[details['vehicle']] ?? _freight['pickup']!;
        p = f.$1 + f.$2 * km + 10.0 * ((details['helpers'] ?? 0) as num);
      case Service.intercity:
        final perSeat = _intercitySeatKm * km;
        p = details['full_car'] == true ? perSeat * 4 : perSeat * seats;
    }
    return p < _min ? _min.round() : p.round();
  }
}
