import 'package:ai_live_translator/core/localization.dart';
import 'package:ai_live_translator/features/auth/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Uzbek default, live switching and persistence preserve the login form',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/welcome',
        routes: [
          GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
          GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
        ],
      );
      final container = ProviderContainer(
        overrides: [localePreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(() {
        router.dispose();
        container.dispose();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final selected = ref.watch(appLocaleProvider);
              return MaterialApp.router(
                locale: selected == 'system' ? null : Locale(selected),
                supportedLocales: supportedUiLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                localeListResolutionCallback: resolveUiLocale,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Turli tillar.\nBitta suhbat.'), findsOneWidget);
      await tester.tap(find.byTooltip('Interfeys tili'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        find.text('Different languages.\nOne conversation.'),
        findsOneWidget,
      );
      final start = find.text('Get started');
      await tester.scrollUntilVisible(
        start,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'example@example.com',
      );
      await tester.tap(find.byTooltip('Interface language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русский'));
      await tester.pumpAndSettle();
      expect(find.text('С возвращением'), findsOneWidget);
      expect(find.text('example@example.com'), findsOneWidget);
      expect(preferences.getString(uiLocaleStorageKey), 'ru');
      expect(tester.takeException(), isNull);

      final restored = ProviderContainer(
        overrides: [localePreferencesProvider.overrideWithValue(preferences)],
      );
      expect(restored.read(appLocaleProvider), 'ru');
      await restored.read(appLocaleProvider.notifier).select('system');
      expect(preferences.getString(uiLocaleStorageKey), 'system');
      restored.dispose();
    },
  );

  test(
    'device language matches supported languages and falls back to Uzbek',
    () {
      expect(
        resolveUiLocale([const Locale('ru', 'RU')], supportedUiLocales),
        const Locale('ru'),
      );
      expect(
        resolveUiLocale([
          const Locale('fr'),
          const Locale('en', 'US'),
        ], supportedUiLocales),
        const Locale('en'),
      );
      expect(
        resolveUiLocale([const Locale('fr')], supportedUiLocales),
        const Locale('uz'),
      );
      expect(resolveUiLocale(null, supportedUiLocales), const Locale('uz'));
    },
  );

  test('translated usage and history keep runtime values intact', () {
    expect(
      translateUi('uz', '{seconds}s connected', {'seconds': '42'}),
      '42 soniya ulangan',
    );
    expect(
      translateUi('ru', '{minutes} minutes / month', {'minutes': '120'}),
      '120 минут в месяц',
    );
    expect(
      translateUi('en', '{plan} · current plan', {'plan': 'Pro'}),
      'Pro · current plan',
    );
  });
}
