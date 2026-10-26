import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'translations.dart';

const supportedUiLocales = [Locale('uz'), Locale('en'), Locale('ru')];
const uiLanguageNames = {'uz': 'O‘zbekcha', 'en': 'English', 'ru': 'Русский'};
const uiLocaleStorageKey = 'interface_language';

final localePreferencesProvider = Provider<SharedPreferences?>((ref) => null);
final appLocaleProvider = StateNotifierProvider<AppLocaleController, String>(
  (ref) => AppLocaleController(ref.watch(localePreferencesProvider)),
);

class AppLocaleController extends StateNotifier<String> {
  AppLocaleController(this.preferences) : super(_load(preferences));
  final SharedPreferences? preferences;

  static String _load(SharedPreferences? preferences) {
    final saved = preferences?.getString(uiLocaleStorageKey);
    return saved == 'system' || uiLanguageNames.containsKey(saved)
        ? saved!
        : 'uz';
  }

  Future<void> select(String code) async {
    if (code != 'system' && !uiLanguageNames.containsKey(code)) return;
    state = code;
    if (preferences != null) {
      final saved = await preferences!.setString(uiLocaleStorageKey, code);
      if (!saved) throw StateError('Could not save interface language.');
    }
  }
}

Locale resolveUiLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final locale in preferred ?? <Locale>[]) {
    for (final candidate in supported) {
      if (locale.languageCode == candidate.languageCode) return candidate;
    }
  }
  return const Locale('uz');
}

String translateUi(
  String language,
  String source, [
  Map<String, String> args = const {},
]) {
  var result = uiTranslations[language]?[source] ?? source;
  for (final entry in args.entries) {
    result = result.replaceAll('{${entry.key}}', entry.value);
  }
  return result;
}

extension UiLocalization on BuildContext {
  String tr(String source, [Map<String, String> args = const {}]) =>
      translateUi(Localizations.localeOf(this).languageCode, source, args);

  String languageName(String code) => tr(switch (code) {
    'en' => 'English',
    'de' => 'German',
    'ru' => 'Russian',
    'tr' => 'Turkish',
    'uz' => 'Uzbek · experimental',
    _ => code,
  });

  String errorText(Object error) {
    if (error is AuthException) {
      return tr(switch (error.code) {
        'invalid_credentials' => 'Email or password is incorrect.',
        'email_not_confirmed' => 'Confirm your email before signing in.',
        'user_already_exists' ||
        'email_exists' => 'This email is already registered.',
        'weak_password' =>
          'Choose a stronger password with at least 6 characters.',
        'over_email_send_rate_limit' ||
        'over_request_rate_limit' => 'Too many requests. Please wait.',
        'signup_disabled' => 'Account registration is currently unavailable.',
        _ => 'Could not complete sign-in. Check your details and connection.',
      });
    }
    final source = error.toString();
    // Only known application messages reach the UI; provider/plugin details stay hidden.
    if (uiTranslations['uz']!.containsKey(source)) return tr(source);
    return tr('Something went wrong. Check your connection and try again.');
  }
}
