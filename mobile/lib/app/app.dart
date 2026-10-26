import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api.dart';
import '../core/localization.dart';
import '../core/browser_locale.dart'
    if (dart.library.js_interop) '../core/browser_locale_web.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/home_screen.dart';
import '../features/conversation/room_screen.dart';
import '../features/translation/live_screen.dart';
import '../features/devices/device_screen.dart';
import '../features/history/history_screen.dart';
import '../features/subscription/subscription_screen.dart';
import '../features/settings/settings_screen.dart';

final themeModeProvider = StateProvider((ref) => ThemeMode.system);

class AuthRefresh extends ChangeNotifier {
  AuthRefresh(SupabaseClient client) {
    subscription = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) recovery = true;
      if (state.event == AuthChangeEvent.signedOut) recovery = false;
      notifyListeners();
    });
  }
  bool recovery = false;
  late StreamSubscription<AuthState> subscription;
  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}

class TranslatorApp extends ConsumerStatefulWidget {
  const TranslatorApp({super.key});
  @override
  ConsumerState<TranslatorApp> createState() => _TranslatorAppState();
}

class _TranslatorAppState extends ConsumerState<TranslatorApp> {
  late final refresh = AuthRefresh(ref.read(supabaseProvider));
  late final GoRouter router = GoRouter(
    initialLocation: '/welcome',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(supabaseProvider).auth.currentSession != null;
      final path = state.uri.path;
      if (refresh.recovery && signedIn && path != '/reset') return '/reset';
      if (!signedIn && path != '/login' && path != '/welcome') return '/login';
      if (signedIn && (path == '/login' || path == '/welcome')) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/reset',
        builder: (_, _) => ResetScreen(
          onComplete: () {
            refresh.recovery = false;
            router.go('/');
          },
        ),
      ),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/create',
        builder: (_, _) => const RoomScreen(join: false),
      ),
      GoRoute(path: '/join', builder: (_, _) => const RoomScreen(join: true)),
      GoRoute(
        path: '/live/:id',
        builder: (_, state) => LiveScreen(
          roomId: state.pathParameters['id']!,
          code: state.extra as String?,
        ),
      ),
      GoRoute(path: '/devices', builder: (_, _) => const DeviceScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(
        path: '/subscription',
        builder: (_, _) => const SubscriptionScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    refresh.dispose();
    super.dispose();
  }

  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff246bfd),
      brightness: brightness,
      surface: brightness == Brightness.dark
          ? const Color(0xff0b1427)
          : const Color(0xfff6f8fc),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'AI Live Translator',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: ref.watch(themeModeProvider),
    locale: ref.watch(appLocaleProvider) == 'system'
        ? null
        : Locale(ref.watch(appLocaleProvider)),
    supportedLocales: supportedUiLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    localeListResolutionCallback: resolveUiLocale,
    builder: (context, child) {
      updateDocumentLanguage(Localizations.localeOf(context).languageCode);
      return child!;
    },
    routerConfig: router,
  );
}
