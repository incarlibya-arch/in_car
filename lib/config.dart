/// إعدادات التطبيق — غيّر القيم هنا فقط.
class AppConfig {
  // من Supabase Dashboard ← Project Settings ← API
  // تقدر تكتبهم هنا مباشرة، أو تمررهم وقت البناء:
  // flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR-PROJECT.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: 'YOUR-ANON-KEY');

  // الخريطة: بلاطات OpenStreetMap للتطوير والتجربة فقط.
  // قبل الإطلاق التجاري بدّلها بمزوّد بلاطات (أو سيرفرك الخاص)، لأن سياسة
  // OSM لا تسمح بالاستخدام التجاري الكثيف.
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const tileUserAgent = 'ly.incar.app';

  // حساب المسار: خادم OSRM التجريبي العام. للإطلاق شغّل OSRM على سيرفرك.
  static const osrmUrl = 'https://router.project-osrm.org';

  // البحث عن العناوين: Nominatim (استخدام خفيف فقط، طلب واحد في الثانية).
  static const nominatimUrl = 'https://nominatim.openstreetmap.org';

  // مركز الخريطة الافتراضي: ميدان الشهداء، طرابلس
  static const defaultLat = 32.8955;
  static const defaultLng = 13.1800;

  static const minFare = 5.0; // د.ل — أقل سعر يقدر الراكب يقترحه (المعادلات في lib/data.dart)

  // الإشعارات (Firebase) — اتركها فاضية لو ما جهزتش Firebase، والتطبيق يشتغل بإشعارات داخلية بس.
  // القيم من Firebase Console ← Project settings ← Your apps.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseAndroidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const firebaseWebAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY'); // للويب/الآيفون
  static bool get pushEnabled => firebaseApiKey.isNotEmpty && firebaseProjectId.isNotEmpty;

  static const countryCode = '+218';
}
