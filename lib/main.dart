import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/sign_in_screen.dart';
import 'utils/theme.dart';
import 'services/firebase_service.dart';
import 'services/group_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Remembered sign-in context (group + user) drives which mode the app runs
  // in, so it loads before any screen builds.
  await GroupSession.load();

  // Portrait only. The platform manifests (Info.plist on iOS, the activity's
  // screenOrientation on Android) enforce this too; this is the runtime half,
  // and it also covers Android where the manifest alone is easy to miss.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Firebase Functions service (HTTP-based)
  try {
    await FirebaseService.instance.initialize();
    debugPrint('Firebase Functions service initialized successfully');
  } catch (e) {
    debugPrint('Firebase Functions initialization failed: $e');
    // Continue without Firebase for offline-only mode
  }

  runApp(
    const ProviderScope(
      child: InSessionApp(),
    ),
  );
}

class InSessionApp extends StatelessWidget {
  const InSessionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InSession - Charleston Law Event Scanner',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      // Sign-in gate: restores the remembered session instantly, or asks
      // for Microsoft 365 sign-in + group selection once per device.
      home: const SignInScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
