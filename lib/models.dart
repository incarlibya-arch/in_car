import 'package:latlong2/latlong.dart';

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

// ---------- الخدمات ----------

enum Service { city, intercity, courier, freight }

extension ServiceLabel on Service {
  String get label => const {
        Service.city: 'مشوار',
        Service.intercity: 'بين المدن',
        Service.courier: 'توصيل طرد',
        Service.freight: 'نقل بضائع',
      }[this]!;
}

Service serviceFrom(String? s) => Service.values.firstWhere((e) => e.name == s, orElse: () => Service.city);

const vehicleTypes = {
  'car': 'سيارة صالون',
  'van': 'سيارة عائلية / فان',
  'pickup': 'بيك آب (ربع نقل)',
  'small_truck': 'شاحنة صغيرة',
  'large_truck': 'شاحنة كبيرة',
};

const paymentMethods = {
  'cash': 'كاش',
  'bank_transfer': 'تحويل مصرفي',
  'sadad': 'سداد',
  'mobicash': 'موبي كاش',
  'other': 'طريقة ثانية',
};

String paymentLabel(String k) => paymentMethods[k] ?? k;

const parcelSizes = {'small': 'صغير (ظرف أو كيس)', 'medium': 'متوسط (كرتونة)', 'large': 'كبير'};

/// أعمدة الملف الشخصي المسموح بقراءتها (رقم الهاتف مخفي ويوصل عبر Api.partyPhone)
const profileColumns =
    'id,full_name,role,car_model,car_color,plate,rating,rating_count,services,vehicle_type,driver_status,driver_note,payment_methods';

class Profile {
  final String id;
  final String fullName;
  final String? phone;
  final String role; // passenger | driver
  final String? carModel;
  final String? carColor;
  final String? plate;
  final double rating;
  final int ratingCount;
  final List<Service> services;
  final String vehicleType;
  final String driverStatus; // pending | approved | rejected
  final String? driverNote;
  final List<String> paymentMethods;

  Profile({
    required this.id,
    required this.fullName,
    this.phone,
    required this.role,
    this.carModel,
    this.carColor,
    this.plate,
    this.rating = 5,
    this.ratingCount = 0,
    this.services = const [Service.city],
    this.vehicleType = 'car',
    this.driverStatus = 'pending',
    this.driverNote,
    this.paymentMethods = const ['cash'],
  });

  bool get isDriver => role == 'driver';
  bool get isApproved => driverStatus == 'approved';
  String get carLabel =>
      [carModel, carColor].where((e) => e != null && e.isNotEmpty).join(' · ');
  String get vehicleLabel => vehicleTypes[vehicleType] ?? vehicleType;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'],
        fullName: m['full_name'] ?? '',
        phone: m['phone'],
        role: m['role'] ?? 'passenger',
        carModel: m['car_model'],
        carColor: m['car_color'],
        plate: m['plate'],
        rating: _d(m['rating']),
        ratingCount: m['rating_count'] ?? 0,
        services: ((m['services'] as List?) ?? const ['city']).map((e) => serviceFrom(e as String)).toList(),
        vehicleType: m['vehicle_type'] ?? 'car',
        driverStatus: m['driver_status'] ?? 'pending',
        driverNote: m['driver_note'],
        paymentMethods: ((m['payment_methods'] as List?) ?? const ['cash']).map((e) => e.toString()).toList(),
      );
}

enum RideStatus { open, accepted, arrived, started, completed, cancelled }

RideStatus _status(String s) =>
    RideStatus.values.firstWhere((e) => e.name == s, orElse: () => RideStatus.open);

class Ride {
  final String id;
  final String passengerId;
  final LatLng pickup;
  final String pickupLabel;
  final LatLng dropoff;
  final String dropoffLabel;
  final double distanceKm;
  final int durationMin;
  final double offeredPrice;
  final double? finalPrice;
  final String? driverId;
  final RideStatus status;
  final String? comment;
  final int? passengerRating;
  final DateTime createdAt;
  final Service service;
  final Map<String, dynamic> details;
  final DateTime? scheduledAt;
  final int? seats;
  final double? commission;
  final String paymentMethod;
  final bool paid;

  Ride({
    required this.id,
    required this.passengerId,
    required this.pickup,
    required this.pickupLabel,
    required this.dropoff,
    required this.dropoffLabel,
    required this.distanceKm,
    required this.durationMin,
    required this.offeredPrice,
    this.finalPrice,
    this.driverId,
    required this.status,
    this.comment,
    this.passengerRating,
    required this.createdAt,
    this.service = Service.city,
    this.details = const {},
    this.scheduledAt,
    this.seats,
    this.commission,
    this.paymentMethod = 'cash',
    this.paid = false,
  });

  bool get isActive =>
      status == RideStatus.accepted || status == RideStatus.arrived || status == RideStatus.started;

  /// رحلة محجوزة لوقت بعد أكثر من 30 دقيقة
  bool get isUpcoming =>
      scheduledAt != null && scheduledAt!.isAfter(DateTime.now().add(const Duration(minutes: 30)));

  /// سطر يوصف تفاصيل الخدمة (الطرد، البضاعة، المقاعد)
  String get detailsLine {
    switch (service) {
      case Service.courier:
        return [
          if (details['item'] != null) 'الطرد: ${details['item']}',
          if (details['size'] != null) parcelSizes[details['size']] ?? '',
          if (details['recipient_name'] != null) 'المستلم: ${details['recipient_name']}',
        ].where((e) => e.isNotEmpty).join(' · ');
      case Service.freight:
        return [
          vehicleTypes[details['vehicle']] ?? '',
          if (details['description'] != null) details['description'].toString(),
          if ((details['helpers'] ?? 0) > 0) 'عمّال: ${details['helpers']}',
        ].where((e) => e.isNotEmpty).join(' · ');
      case Service.intercity:
        return details['full_car'] == true ? 'السيارة كاملة' : '${seats ?? 1} مقعد';
      case Service.city:
        return '';
    }
  }

  factory Ride.fromMap(Map<String, dynamic> m) => Ride(
        id: m['id'],
        passengerId: m['passenger_id'],
        pickup: LatLng(_d(m['pickup_lat']), _d(m['pickup_lng'])),
        pickupLabel: m['pickup_label'] ?? '',
        dropoff: LatLng(_d(m['dropoff_lat']), _d(m['dropoff_lng'])),
        dropoffLabel: m['dropoff_label'] ?? '',
        distanceKm: _d(m['distance_km']),
        durationMin: m['duration_min'] ?? 0,
        offeredPrice: _d(m['offered_price']),
        finalPrice: m['final_price'] == null ? null : _d(m['final_price']),
        driverId: m['driver_id'],
        status: _status(m['status'] ?? 'open'),
        comment: m['comment'],
        passengerRating: m['passenger_rating'],
        createdAt: _t(m['created_at']) ?? DateTime.now(),
        service: serviceFrom(m['service']),
        details: Map<String, dynamic>.from((m['details'] as Map?) ?? const {}),
        scheduledAt: _t(m['scheduled_at']),
        seats: m['seats'],
        commission: m['commission'] == null ? null : _d(m['commission']),
        paymentMethod: m['payment_method'] ?? 'cash',
        paid: m['paid'] == true,
      );
}

class Offer {
  final String id;
  final String rideId;
  final String driverId;
  final double price;
  final int? etaMin;
  final String status;

  Offer({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.price,
    this.etaMin,
    required this.status,
  });

  factory Offer.fromMap(Map<String, dynamic> m) => Offer(
        id: m['id'],
        rideId: m['ride_id'],
        driverId: m['driver_id'],
        price: _d(m['price']),
        etaMin: m['eta_min'],
        status: m['status'] ?? 'pending',
      );
}

/// مكان مختار على الخريطة أو من البحث
class Place {
  final LatLng point;
  final String label;
  const Place(this.point, this.label);
}

/// نتيجة حساب المسار
class RouteInfo {
  final List<LatLng> points;
  final double km;
  final int minutes;
  const RouteInfo(this.points, this.km, this.minutes);
}

// ---------- المحادثة والإشعارات والوثائق ----------

class ChatMessage {
  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;
  ChatMessage({required this.id, required this.senderId, required this.body, required this.createdAt});
  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'],
        senderId: m['sender_id'],
        body: m['body'] ?? '',
        createdAt: _t(m['created_at']) ?? DateTime.now(),
      );
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });
  String? get rideId => data['ride_id'] as String?;
  String get type => (data['type'] ?? '') as String;
  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'],
        title: m['title'] ?? '',
        body: m['body'] ?? '',
        data: Map<String, dynamic>.from((m['data'] as Map?) ?? const {}),
        read: m['read'] == true,
        createdAt: _t(m['created_at']) ?? DateTime.now(),
      );
}

const docTypes = {
  'license': 'رخصة القيادة',
  'id_card': 'البطاقة الشخصية أو جواز السفر',
  'registration': 'كتيب السيارة',
  'car_photo': 'صورة السيارة مع اللوحة',
};

class DriverDoc {
  final String docType;
  final String path;
  final String status;
  DriverDoc({required this.docType, required this.path, required this.status});
  factory DriverDoc.fromMap(Map<String, dynamic> m) =>
      DriverDoc(docType: m['doc_type'], path: m['path'], status: m['status'] ?? 'pending');
}

class SosAlert {
  final String id;
  final String? rideId;
  final String userId;
  final double? lat;
  final double? lng;
  final bool resolved;
  final DateTime createdAt;
  SosAlert({
    required this.id,
    this.rideId,
    required this.userId,
    this.lat,
    this.lng,
    required this.resolved,
    required this.createdAt,
  });
  factory SosAlert.fromMap(Map<String, dynamic> m) => SosAlert(
        id: m['id'],
        rideId: m['ride_id'],
        userId: m['user_id'],
        lat: m['lat'] == null ? null : _d(m['lat']),
        lng: m['lng'] == null ? null : _d(m['lng']),
        resolved: m['resolved'] == true,
        createdAt: _t(m['created_at']) ?? DateTime.now(),
      );
}

// ---------- المحفظة ----------

class AppSettings {
  final double commissionRate; // 0.07 = 7%
  final double minBalance;
  final DateTime? freeUntil;
  final String topupInfo;
  final bool requireVerification;
  final String emergencyPhone;
  final String supportPhone;
  const AppSettings({
    this.commissionRate = 0,
    this.minBalance = 0,
    this.freeUntil,
    this.topupInfo = '',
    this.requireVerification = true,
    this.emergencyPhone = '',
    this.supportPhone = '',
  });

  bool get isFreePeriod => freeUntil != null && freeUntil!.isAfter(DateTime.now());
  bool get chargesCommission => commissionRate > 0 && !isFreePeriod;
  bool canWork(double balance) => !chargesCommission || balance >= minBalance;
  String get ratePercent => '${(commissionRate * 100).toStringAsFixed(commissionRate * 100 % 1 == 0 ? 0 : 1)}%';

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        commissionRate: _d(m['commission_rate']),
        minBalance: _d(m['min_balance']),
        freeUntil: m['free_until'] == null ? null : DateTime.tryParse(m['free_until'])?.toLocal(),
        topupInfo: m['topup_info'] ?? '',
        requireVerification: m['require_verification'] != false,
        emergencyPhone: m['emergency_phone'] ?? '',
        supportPhone: m['support_phone'] ?? '',
      );
}

class WalletTx {
  final String id;
  final double amount;
  final String kind; // topup | commission | adjustment | refund
  final String? note;
  final DateTime createdAt;
  WalletTx({required this.id, required this.amount, required this.kind, this.note, required this.createdAt});

  String get kindLabel => const {
        'topup': 'شحن رصيد',
        'commission': 'عمولة رحلة',
        'adjustment': 'تعديل من الإدارة',
        'refund': 'استرجاع',
      }[kind] ??
      kind;

  factory WalletTx.fromMap(Map<String, dynamic> m) => WalletTx(
        id: m['id'],
        amount: _d(m['amount']),
        kind: m['kind'] ?? '',
        note: m['note'],
        createdAt: DateTime.tryParse(m['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
      );
}

const topupMethods = {
  'cash_agent': 'نقداً عند المكتب أو الوكيل',
  'bank_transfer': 'تحويل مصرفي',
  'sadad': 'سداد',
  'mobicash': 'موبي كاش',
  'other': 'طريقة أخرى',
};

class TopupRequest {
  final String id;
  final String driverId;
  final double amount;
  final String method;
  final String? reference;
  final String status; // pending | approved | rejected
  final String? adminNote;
  final DateTime createdAt;
  TopupRequest({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.method,
    this.reference,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  String get methodLabel => topupMethods[method] ?? method;
  String get statusLabel => const {'pending': 'قيد المراجعة', 'approved': 'تم الشحن', 'rejected': 'مرفوض'}[status] ?? status;

  factory TopupRequest.fromMap(Map<String, dynamic> m) => TopupRequest(
        id: m['id'],
        driverId: m['driver_id'],
        amount: _d(m['amount']),
        method: m['method'] ?? 'other',
        reference: m['reference'],
        status: m['status'] ?? 'pending',
        adminNote: m['admin_note'],
        createdAt: DateTime.tryParse(m['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
      );
}
