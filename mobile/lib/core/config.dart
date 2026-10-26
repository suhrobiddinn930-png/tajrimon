import 'package:flutter/foundation.dart';

class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiUrl = String.fromEnvironment('API_URL');
  static const allowInsecure = bool.fromEnvironment('ALLOW_INSECURE_LOCAL_DEV');
  static String get authRedirect => kIsWeb
      ? '${Uri.base.origin}/app/'
      : 'ai.live.translator://auth-callback/';
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseKey.isNotEmpty &&
      apiUrl.isNotEmpty &&
      (Uri.tryParse(apiUrl)?.scheme == 'https' || allowInsecure);
}
