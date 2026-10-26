import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'models.dart';

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final supabaseProvider = Provider((ref) => Supabase.instance.client);
final apiProvider = Provider((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return Api(ref.read(supabaseProvider), client);
});
final languagePairProvider = StateProvider((ref) {
  ref.watch(accountProvider);
  return ('en', 'de');
});
// Recompute private data when the account changes, including sign-out/sign-in.
final authEventsProvider = StreamProvider((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});
final accountProvider = Provider<String?>((ref) {
  ref.watch(authEventsProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});
final languagesProvider = FutureProvider<List<String>>((ref) async {
  final data =
      await ref.read(apiProvider).request('GET', '/languages')
          as Map<String, dynamic>;
  return List<String>.from(data['languages'] as List);
});
final allowanceProvider = FutureProvider((ref) async {
  final account = ref.watch(accountProvider);
  if (account == null) throw const AppFailure('Please sign in again.');
  return Allowance.fromJson(
    await ref.read(apiProvider).request('GET', '/usage/me')
        as Map<String, dynamic>,
  );
});
final historyProvider = FutureProvider((ref) async {
  final account = ref.watch(accountProvider);
  if (account == null) throw const AppFailure('Please sign in again.');
  return await ref.read(apiProvider).request('GET', '/history')
      as List<dynamic>;
});

class Api {
  Api(this.auth, this.client);
  final SupabaseClient auth;
  final http.Client client;

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final session = auth.auth.currentSession;
    if (session == null) throw const AppFailure('Please sign in again.');
    final request = http.Request(method, Uri.parse('${AppConfig.apiUrl}$path'));
    request.headers.addAll({
      'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json',
    });
    if (data != null) request.body = jsonEncode(data);
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw AppFailure(
          body['error']?['message'] as String? ??
              'Request failed. Please retry.',
        );
      }
      return body;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        'Connection unavailable. Check your internet and retry.',
      );
    }
  }

  Future<Conversation> room(String id) async => Conversation.fromJson(
    await request('GET', '/conversations/$id') as Map<String, dynamic>,
  );
}
