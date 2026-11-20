import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'api.dart';

/// إشعارات Firebase (تصل حتى لو التطبيق مقفول).
/// لو ما جهزتش Firebase في config.dart، الدالة ما تعمل شي، والإشعارات الداخلية تبقى شغالة.
class Push {
  static bool _ready = false;
  static bool _started = false;

  static FirebaseOptions? get _options {
    if (!AppConfig.pushEnabled) return null;
    final appId = kIsWeb
        ? AppConfig.firebaseWebAppId
        : defaultTargetPlatform == TargetPlatform.iOS
            ? AppConfig.firebaseIosAppId
            : AppConfig.firebaseAndroidAppId;
    if (appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: appId,
      messagingSenderId: AppConfig.firebaseSenderId,
      projectId: AppConfig.firebaseProjectId,
    );
  }

  /// يطلب الإذن ويحفظ رمز الجهاز في Supabase. ينادى بعد تسجيل الدخول.
  static Future<void> register() async {
    final opts = _options;
    if (opts == null || Api.uid == null || _started) return;
    _started = true;
    try {
      if (!_ready) {
        await Firebase.initializeApp(options: opts);
        _ready = true;
      }
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await fm.getToken(vapidKey: kIsWeb ? AppConfig.firebaseVapidKey : null);
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      if (token != null) await Api.saveDeviceToken(token, platform);
      fm.onTokenRefresh.listen((t) => Api.saveDeviceToken(t, platform));
    } catch (e) {
      debugPrint('Push not available: $e');
    }
  }
}
