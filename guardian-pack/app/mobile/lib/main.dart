import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth.dart';
import 'firebase_options.dart';
import 'theme/theme.dart';
import 'ui/auth/sign_in_screen.dart';
import 'theme/theme_mode.dart';
import 'theme/tokens.dart';
import 'ui/shell.dart';
import 'ui/splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: WpColors.navy,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final themeMode = await loadThemeMode();
  runApp(ProviderScope(
    overrides: [initialThemeModeProvider.overrideWithValue(themeMode)],
    child: const WatchPackApp(),
  ));
}

class WatchPackApp extends ConsumerWidget {
  const WatchPackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'WatchPack',
      debugShowCheckedModeBanner: false,
      theme: wpLightTheme,
      darkTheme: wpDarkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: const _Boot(),
    );
  }
}

/// Signed out → sign-in screen. Signed in → the tabs (which wait for the profile).
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const SplashScreen(),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth error: $e'))),
      data: (user) => user == null ? const SignInScreen(key: ValueKey('signin')) : const Shell(key: ValueKey('shell')),
    );
  }
}

/// Splash while Firebase comes up (well under a second), then the app.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<void> _init = Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _init,
      builder: (_, snap) {
        final ready = snap.connectionState == ConnectionState.done && !snap.hasError;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: ready
              ? const _AuthGate()
              : snap.hasError
                  ? Scaffold(
                      key: const ValueKey('boot-error'),
                      backgroundColor: WpColors.navy,
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(WpSpace.xl),
                          child: Text('Could not start: ${snap.error}', style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    )
                  : const SplashScreen(key: ValueKey('splash')),
        );
      },
    );
  }
}
