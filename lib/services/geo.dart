import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models.dart';

/// الموقع الحالي، والمسارات، والبحث عن العناوين، والسعر المقترح.
class Geo {
  // المتصفح ما يسمحش بتغيير User-Agent، فنبعتوه في نسخة الجوال بس
  static Map<String, String> get _headers =>
      kIsWeb ? const {} : const {'User-Agent': '${AppConfig.tileUserAgent} (ride app)'};

  /// يطلب إذن الموقع ويرجع موقع الجهاز، أو null لو رفض المستخدم.
  static Future<LatLng?> myLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  /// مسار القيادة عبر OSRM. لو فشل، يرجع خط مستقيم مع مسافة تقديرية.
  static Future<RouteInfo> route(LatLng a, LatLng b) async {
    try {
      final url = Uri.parse('${AppConfig.osrmUrl}/route/v1/driving/'
          '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
          '?overview=full&geometries=geojson');
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final r = (j['routes'] as List).first;
        final coords = (r['geometry']['coordinates'] as List)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        return RouteInfo(
          coords,
          (r['distance'] as num) / 1000,
          max(1, ((r['duration'] as num) / 60).round()),
        );
      }
    } catch (_) {}
    final km = const Distance().as(LengthUnit.Meter, a, b) / 1000 * 1.35;
    return RouteInfo([a, b], km, max(3, (km / 30 * 60).round()));
  }

  /// بحث عن عنوان داخل ليبيا (Nominatim).
  static Future<List<Place>> search(String q) async {
    if (q.trim().length < 2) return [];
    final url = Uri.parse('${AppConfig.nominatimUrl}/search'
        '?format=jsonv2&countrycodes=ly&accept-language=ar&limit=8&q=${Uri.encodeQueryComponent(q)}');
    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list
          .map((e) => Place(
                LatLng(double.parse(e['lat']), double.parse(e['lon'])),
                _short(e['display_name'] ?? ''),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// اسم مختصر لنقطة على الخريطة.
  static Future<String> labelFor(LatLng p) async {
    final url = Uri.parse('${AppConfig.nominatimUrl}/reverse'
        '?format=jsonv2&accept-language=ar&zoom=17&lat=${p.latitude}&lon=${p.longitude}');
    try {
      final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final s = _short(j['display_name'] ?? '');
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return 'نقطة على الخريطة';
  }

  static String _short(String s) => s.split('،').expand((e) => e.split(',')).take(2).map((e) => e.trim()).join('، ');
}
