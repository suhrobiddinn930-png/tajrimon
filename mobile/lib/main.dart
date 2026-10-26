import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app/app.dart';
import 'core/config.dart';
import 'core/localization.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(
      MaterialApp(
        locale: const Locale('uz'),
        supportedLocales: supportedUiLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Builder(
                builder: (context) => Text(
                  context.tr(
                    'Configuration required. Follow mobile/README.md to set the Supabase URL, publishable key and HTTPS API URL.',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
  );
  SharedPreferences? preferences;
  try {
    preferences = await SharedPreferences.getInstance();
  } catch (_) {
    // Storage can be unavailable in a private browser; language switching still works.
  }
  runApp(
    ProviderScope(
      overrides: [localePreferencesProvider.overrideWithValue(preferences)],
      child: const TranslatorApp(),
    ),
  );
}
