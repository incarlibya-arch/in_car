import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'config.dart';
import 'theme.dart';

/// الخريطة المشتركة بين كل الشاشات.
class AppMap extends StatelessWidget {
  final MapController? controller;
  final LatLng? center;
  final LatLng? pickup;
  final LatLng? dropoff;
  final LatLng? car;
  final List<LatLng> route;
  final void Function(LatLng)? onTap;

  const AppMap({
    super.key,
    this.controller,
    this.center,
    this.pickup,
    this.dropoff,
    this.car,
    this.route = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center ?? pickup ?? const LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
        initialZoom: 14,
        onTap: onTap == null ? null : (_, p) => onTap!(p),
      ),
      children: [
        TileLayer(urlTemplate: AppConfig.tileUrl, userAgentPackageName: AppConfig.tileUserAgent),
        if (route.length > 1)
          PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: AppColors.ink)]),
        MarkerLayer(markers: [
          if (pickup != null)
            Marker(point: pickup!, width: 28, height: 28, child: const _Pin(square: false)),
          if (dropoff != null)
            Marker(point: dropoff!, width: 28, height: 28, child: const _Pin(square: true)),
          if (car != null)
            Marker(
              point: car!,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
                child: const Icon(Icons.directions_car, color: AppColors.ink, size: 22),
              ),
            ),
        ]),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  final bool square;
  const _Pin({required this.square});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: square ? AppColors.ink : Colors.white,
            border: Border.all(color: AppColors.ink, width: 5),
            borderRadius: BorderRadius.circular(square ? 4 : 10),
          ),
        ),
      );
}

/// اللوحة البيضاء في أسفل الشاشة فوق الخريطة.
class BottomSheetCard extends StatelessWidget {
  final List<Widget> children;
  const BottomSheetCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x220F1B2D), blurRadius: 24, offset: Offset(0, -6))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// مبلغ بالدينار الليبي
class Money extends StatelessWidget {
  final num value;
  final double size;
  const Money(this.value, {super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(
            text: value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' د.ل', style: TextStyle(fontSize: size * .55, fontWeight: FontWeight.w600)),
        ]),
        softWrap: false,
      );
}

/// صورة رمزية بالحرف الأول
class Initial extends StatelessWidget {
  final String name;
  final double size;
  const Initial(this.name, {super.key, this.size = 48});
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.line,
        child: Text(name.isEmpty ? '؟' : name.characters.first,
            style: TextStyle(fontSize: size * .4, fontWeight: FontWeight.w700, color: AppColors.mute)),
      );
}

/// نقطتي الانطلاق والوصول
class StopsBox extends StatelessWidget {
  final String from;
  final String to;
  final VoidCallback? onTapFrom;
  final VoidCallback? onTapTo;
  const StopsBox({super.key, required this.from, required this.to, this.onTapFrom, this.onTapTo});

  @override
  Widget build(BuildContext context) {
    Widget row(bool square, String label, String value, VoidCallback? tap) => InkWell(
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: square ? AppColors.ink : null,
                  border: Border.all(color: AppColors.ink, width: 3),
                  borderRadius: BorderRadius.circular(square ? 3 : 6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        row(false, 'من', from, onTapFrom),
        const Divider(height: 1, color: AppColors.line),
        row(true, 'إلى', to, onTapTo),
      ]),
    );
  }
}

void showMsg(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
