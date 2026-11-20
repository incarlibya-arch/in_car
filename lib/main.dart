import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';
import 'screens/auth_screens.dart';
import 'screens/driver_screens.dart';
import 'screens/passenger_screens.dart';
import 'screens/notifications_screen.dart';
import 'services/api.dart';
import 'services/push.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  runApp(const InCarApp());
}

class InCarApp extends StatelessWidget {
  const InCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'in car',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: buildTheme(),
      locale: const Locale('ar', 'LY'),
      supportedLocales: const [Locale('ar', 'LY'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// يقرر أي شاشة تظهر: الدخول، إكمال الملف، الراكب، أو السائق.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        if (Supabase.instance.client.auth.currentSession == null) return const PhoneScreen();
        return FutureBuilder<Profile?>(
          future: Api.myProfile(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final p = snap.data;
            if (p == null) return const ProfileSetupScreen();
            Push.register();
            return InAppNotifier(child: p.isDriver ? DriverHome(me: p) : PassengerHome(me: p));
          },
        );
      },
    );
  }
}

/// يعيد بناء AuthGate بعد تغيير الملف الشخصي أو الدور.
void restartToGate(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (_) => false,
  );
}
