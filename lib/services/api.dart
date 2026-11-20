import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';

final _db = Supabase.instance.client;

/// كل التعامل مع Supabase في مكان واحد.
class Api {
  static String? get uid => _db.auth.currentUser?.id;

  // ---------- الدخول برقم الهاتف ----------

  static String normalizePhone(String input) {
    var p = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('218')) p = p.substring(3);
    if (p.startsWith('0')) p = p.substring(1);
    return '${AppConfig.countryCode}$p';
  }

  static Future<void> sendOtp(String phone) => _db.auth.signInWithOtp(phone: phone);

  static Future<void> verifyOtp(String phone, String code) =>
      _db.auth.verifyOTP(type: OtpType.sms, phone: phone, token: code);

  static Future<void> signOut() => _db.auth.signOut();

  // ---------- الملف الشخصي ----------

  static final Map<String, Profile> _cache = {};

  static Future<Profile?> myProfile() async {
    final id = uid;
    if (id == null) return null;
    final m = await _db.from('profiles').select(profileColumns).eq('id', id).maybeSingle();
    if (m == null) return null;
    return _cache[id] = Profile.fromMap(m);
  }

  static Future<void> saveProfile({
    required String fullName,
    required String role,
    String? carModel,
    String? carColor,
    String? plate,
    List<Service> services = const [Service.city],
    String vehicleType = 'car',
  }) async {
    final row = {
      'full_name': fullName,
      'phone': _db.auth.currentUser?.phone,
      'role': role,
      'car_model': carModel,
      'car_color': carColor,
      'plate': plate,
      'services': services.map((e) => e.name).toList(),
      'vehicle_type': vehicleType,
    };
    final exists = await _db.from('profiles').select('id').eq('id', uid!).maybeSingle();
    if (exists == null) {
      await _db.from('profiles').insert({'id': uid, ...row});
    } else {
      await _db.from('profiles').update(row).eq('id', uid!);
    }
    _cache.remove(uid);
  }

  static Future<Profile?> profile(String id) async {
    if (_cache[id] != null) return _cache[id];
    final m = await _db.from('profiles').select(profileColumns).eq('id', id).maybeSingle();
    return m == null ? null : (_cache[id] = Profile.fromMap(m));
  }

  static Future<void> loadProfiles(Iterable<String> ids) async {
    final missing = ids.where((i) => !_cache.containsKey(i)).toSet().toList();
    if (missing.isEmpty) return;
    final rows = await _db.from('profiles').select(profileColumns).inFilter('id', missing);
    for (final m in rows) {
      final p = Profile.fromMap(m);
      _cache[p.id] = p;
    }
  }

  static Profile? cached(String id) => _cache[id];

  /// رقم الطرف الثاني — يرجع بس أثناء رحلة نشطة بينكم
  static Future<String?> partyPhone(String userId) async {
    try {
      final r = await _db.rpc('party_phone', params: {'p_user': userId});
      if (r == null || (r as String).isEmpty) return null;
      return r.startsWith('+') ? r : '+$r';
    } catch (_) {
      return null;
    }
  }

  // ---------- الراكب ----------

  static Future<String> createRide({
    required Place pickup,
    required Place dropoff,
    required RouteInfo route,
    required double price,
    Service service = Service.city,
    Map<String, dynamic> details = const {},
    DateTime? scheduledAt,
    int? seats,
    String? comment,
  }) async {
    final row = await _db
        .from('rides')
        .insert({
          'passenger_id': uid,
          'pickup_lat': pickup.point.latitude,
          'pickup_lng': pickup.point.longitude,
          'pickup_label': pickup.label,
          'dropoff_lat': dropoff.point.latitude,
          'dropoff_lng': dropoff.point.longitude,
          'dropoff_label': dropoff.label,
          'distance_km': double.parse(route.km.toStringAsFixed(1)),
          'duration_min': route.minutes,
          'offered_price': price,
          'service': service.name,
          'details': details,
          'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
          'seats': seats,
          'comment': comment,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Stream<Ride?> watchRide(String rideId) => _db
      .from('rides')
      .stream(primaryKey: ['id'])
      .eq('id', rideId)
      .map((rows) => rows.isEmpty ? null : Ride.fromMap(rows.first));

  static Stream<List<Offer>> watchOffers(String rideId) => _db
      .from('offers')
      .stream(primaryKey: ['id'])
      .eq('ride_id', rideId)
      .map((rows) => rows
          .map(Offer.fromMap)
          .where((o) => o.status == 'pending')
          .toList()
        ..sort((a, b) => a.price.compareTo(b.price)));

  static Future<void> raisePrice(String rideId, double newPrice) =>
      _db.from('rides').update({'offered_price': newPrice}).eq('id', rideId);

  static Future<void> cancelOpenRide(String rideId) =>
      _db.from('rides').update({'status': 'cancelled'}).eq('id', rideId);

  static Future<void> acceptOffer(String offerId) =>
      _db.rpc('accept_offer', params: {'p_offer_id': offerId});

  static Future<void> declineOffer(String offerId) =>
      _db.from('offers').update({'status': 'declined'}).eq('id', offerId);

  static Future<void> rateRide(String rideId, int stars) =>
      _db.rpc('rate_ride', params: {'p_ride_id': rideId, 'p_stars': stars});

  /// آخر رحلة غير منتهية للراكب (لاستكمالها بعد إعادة فتح التطبيق)
  static Future<Ride?> myUnfinishedRide() async {
    final rows = await _db
        .from('rides')
        .select()
        .eq('passenger_id', uid!)
        .inFilter('status', ['open', 'accepted', 'arrived', 'started'])
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = Ride.fromMap(rows.first);
    // الرحلات المحجوزة لوقت بعيد ما تفتحش تلقائياً
    return r.isUpcoming ? null : r;
  }

  /// رحلات الراكب المحجوزة القادمة
  static Stream<List<Ride>> watchMyUpcomingRides() => _db
      .from('rides')
      .stream(primaryKey: ['id'])
      .eq('passenger_id', uid!)
      .map((rows) => rows
          .map(Ride.fromMap)
          .where((r) => r.scheduledAt != null && (r.status == RideStatus.open || r.isActive))
          .toList()
        ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!)));

  // ---------- السائق ----------

  /// الطلبات المفتوحة: الفورية من آخر 30 دقيقة، والمحجوزة لين موعدها
  static Stream<List<Ride>> watchOpenRides() => _db
      .from('rides')
      .stream(primaryKey: ['id'])
      .eq('status', 'open')
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) {
        final now = DateTime.now();
        return rows.map(Ride.fromMap).where((r) {
          if (r.passengerId == uid) return false;
          if (r.scheduledAt != null) return r.scheduledAt!.isAfter(now.subtract(const Duration(minutes: 15)));
          return now.difference(r.createdAt).inMinutes < 30;
        }).toList();
      });

  static Stream<List<Ride>> watchMyDriverRides() => _db
      .from('rides')
      .stream(primaryKey: ['id'])
      .eq('driver_id', uid!)
      .map((rows) => rows.map(Ride.fromMap).toList());

  static Stream<List<Offer>> watchMyOffers() => _db
      .from('offers')
      .stream(primaryKey: ['id'])
      .eq('driver_id', uid!)
      .map((rows) => rows.map(Offer.fromMap).toList());

  static Future<void> sendOffer(String rideId, double price, int etaMin) =>
      _db.from('offers').upsert(
        {'ride_id': rideId, 'driver_id': uid, 'price': price, 'eta_min': etaMin, 'status': 'pending'},
        onConflict: 'ride_id,driver_id',
      );

  static Future<void> advanceRide(String rideId, RideStatus to) =>
      _db.rpc('advance_ride', params: {'p_ride_id': rideId, 'p_status': to.name});

  static Future<void> updateMyLocation(double lat, double lng, bool online) =>
      _db.from('driver_locations').upsert({
        'driver_id': uid,
        'lat': lat,
        'lng': lng,
        'is_online': online,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  static Stream<Map<String, dynamic>?> watchDriverLocation(String driverId) => _db
      .from('driver_locations')
      .stream(primaryKey: ['driver_id'])
      .eq('driver_id', driverId)
      .map((rows) => rows.isEmpty ? null : rows.first);

  // ---------- المحادثة ----------

  static Stream<List<ChatMessage>> watchMessages(String rideId) => _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('ride_id', rideId)
      .order('created_at')
      .map((rows) => rows.map(ChatMessage.fromMap).toList());

  static Future<void> sendMessage(String rideId, String body) =>
      _db.from('messages').insert({'ride_id': rideId, 'sender_id': uid, 'body': body});

  // ---------- الإشعارات ----------

  static Stream<List<AppNotification>> watchMyNotifications() => _db
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid!)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromMap).toList());

  static Future<void> markNotificationsRead() =>
      _db.from('notifications').update({'read': true}).eq('user_id', uid!).eq('read', false);

  static Future<void> saveDeviceToken(String token, String platform) => _db.from('device_tokens').upsert({
        'token': token,
        'user_id': uid,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  // ---------- وثائق السائق ----------

  static Future<List<DriverDoc>> myDocuments() async {
    final rows = await _db.from('driver_documents').select().eq('driver_id', uid!);
    return rows.map(DriverDoc.fromMap).toList();
  }

  static Future<void> uploadDocument(String docType, Uint8List bytes, String ext) async {
    final path = '$uid/$docType.$ext';
    await _db.storage.from('driver-docs').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        );
    await _db.from('driver_documents').upsert(
      {'driver_id': uid, 'doc_type': docType, 'path': path, 'status': 'pending'},
      onConflict: 'driver_id,doc_type',
    );
  }

  static Future<String> documentUrl(String path) =>
      _db.storage.from('driver-docs').createSignedUrl(path, 3600);

  // ---------- الطوارئ ----------

  static Future<void> sendSos({String? rideId, double? lat, double? lng}) =>
      _db.from('sos_alerts').insert({'ride_id': rideId, 'user_id': uid, 'lat': lat, 'lng': lng});

  // ---------- المحفظة والعمولة ----------

  static Future<AppSettings> settings() async {
    final m = await _db.from('app_settings').select().eq('id', 1).maybeSingle();
    return m == null ? const AppSettings() : AppSettings.fromMap(m);
  }

  static Stream<AppSettings> watchSettings() => _db
      .from('app_settings')
      .stream(primaryKey: ['id'])
      .eq('id', 1)
      .map((rows) => rows.isEmpty ? const AppSettings() : AppSettings.fromMap(rows.first));

  static Stream<double> watchMyBalance() => _db
      .from('driver_wallets')
      .stream(primaryKey: ['driver_id'])
      .eq('driver_id', uid!)
      .map((rows) => rows.isEmpty ? 0.0 : (rows.first['balance'] as num).toDouble());

  static Future<List<WalletTx>> myTransactions() async {
    final rows = await _db
        .from('wallet_transactions')
        .select()
        .eq('driver_id', uid!)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(WalletTx.fromMap).toList();
  }

  static Stream<List<TopupRequest>> watchMyTopups() => _db
      .from('topup_requests')
      .stream(primaryKey: ['id'])
      .eq('driver_id', uid!)
      .order('created_at', ascending: false)
      .limit(20)
      .map((rows) => rows.map(TopupRequest.fromMap).toList());

  static Future<void> requestTopup(double amount, String method, String? reference) =>
      _db.from('topup_requests').insert({
        'driver_id': uid,
        'amount': amount,
        'method': method,
        'reference': reference,
      });

  // ---------- الإدارة ----------

  static Future<bool> isAdmin() async {
    try {
      return (await _db.rpc('is_admin')) == true;
    } catch (_) {
      return false;
    }
  }

  static Stream<List<TopupRequest>> watchPendingTopups() => _db
      .from('topup_requests')
      .stream(primaryKey: ['id'])
      .eq('status', 'pending')
      .order('created_at')
      .map((rows) => rows.map(TopupRequest.fromMap).toList());

  static Future<void> decideTopup(String id, bool approve, {String? note}) =>
      _db.rpc('admin_decide_topup', params: {'p_request_id': id, 'p_approve': approve, 'p_note': note});

  static Future<void> adjustWallet(String driverId, double amount, String note) =>
      _db.rpc('admin_adjust_wallet', params: {'p_driver': driverId, 'p_amount': amount, 'p_note': note});

  static Future<void> updateSettings({
    required double rate,
    required double minBalance,
    DateTime? freeUntil,
    String? topupInfo,
    bool? requireVerification,
    String? emergencyPhone,
    String? supportPhone,
  }) =>
      _db.from('app_settings').update({
        'commission_rate': rate,
        'min_balance': minBalance,
        'free_until': freeUntil?.toUtc().toIso8601String(),
        if (topupInfo != null) 'topup_info': topupInfo,
        if (requireVerification != null) 'require_verification': requireVerification,
        if (emergencyPhone != null) 'emergency_phone': emergencyPhone,
        if (supportPhone != null) 'support_phone': supportPhone,
      }).eq('id', 1);

  /// يلقى سائق برقم هاتفه (لتعديل رصيده من الإدارة)
  static Future<Profile?> findDriverByPhone(String phone) async {
    final rows = await _db.rpc('admin_find_driver', params: {'p_phone': normalizePhone(phone)}) as List;
    return rows.isEmpty ? null : Profile.fromMap(Map<String, dynamic>.from(rows.first));
  }

  static Future<double> driverBalance(String driverId) async {
    final m = await _db.from('driver_wallets').select('balance').eq('driver_id', driverId).maybeSingle();
    return m == null ? 0 : (m['balance'] as num).toDouble();
  }

  static Future<List<Profile>> pendingDrivers() async {
    final rows = await _db.rpc('admin_pending_drivers') as List;
    return rows.map((m) => Profile.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  static Future<List<DriverDoc>> documentsOf(String driverId) async {
    final rows = await _db.from('driver_documents').select().eq('driver_id', driverId);
    return rows.map(DriverDoc.fromMap).toList();
  }

  static Future<void> setDriverStatus(String driverId, String status, {String? note}) =>
      _db.rpc('admin_set_driver_status', params: {'p_driver': driverId, 'p_status': status, 'p_note': note});

  static Stream<List<SosAlert>> watchOpenSos() => _db
      .from('sos_alerts')
      .stream(primaryKey: ['id'])
      .eq('resolved', false)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(SosAlert.fromMap).toList());

  static Future<void> resolveSos(String id) => _db.from('sos_alerts').update({'resolved': true}).eq('id', id);

  static Future<Ride?> rideById(String id) async {
    final m = await _db.from('rides').select().eq('id', id).maybeSingle();
    return m == null ? null : Ride.fromMap(m);
  }
}

/// رسالة خطأ مفهومة للمستخدم
String friendlyError(Object e) {
  if (e is AuthException) return 'تعذر التحقق: ${e.message}';
  if (e is StorageException) return 'تعذر رفع الملف: ${e.message}';
  if (e is PostgrestException) {
    // 42501 = رفض صلاحيات RLS: عند السائق سببه حساب غير موثّق أو رصيد غير كافي
    if (e.code == '42501') return 'ما تقدرش تقدّم عروض توا. تأكد إن حسابك موثّق ورصيد محفظتك كافي.';
    return e.message;
  }
  return 'صار خطأ، تأكد من الاتصال بالإنترنت وحاول مرة ثانية.';
}
