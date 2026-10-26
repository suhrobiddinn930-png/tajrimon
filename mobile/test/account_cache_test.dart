import 'package:ai_live_translator/core/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountApi extends Api {
  AccountApi(super.auth, super.client);
  String account = 'first';
  int calls = 0;

  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    calls++;
    return path == '/history'
        ? [account]
        : {
            'plan': account,
            'used_seconds': 0,
            'limit_seconds': 600,
            'estimated_cost_usd': 0,
          };
  }
}

void main() {
  test(
    'private history and allowance reload when the account changes',
    () async {
      final auth = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
      );
      final client = http.Client();
      final api = AccountApi(auth, client);
      final container = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(api),
          accountProvider.overrideWithValue('first'),
        ],
      );
      addTearDown(() async {
        container.dispose();
        client.close();
        await auth.dispose();
      });
      expect(await container.read(historyProvider.future), ['first']);
      expect((await container.read(allowanceProvider.future)).plan, 'first');

      api.account = 'second';
      container.updateOverrides([
        apiProvider.overrideWithValue(api),
        accountProvider.overrideWithValue('second'),
      ]);
      expect(await container.read(historyProvider.future), ['second']);
      expect((await container.read(allowanceProvider.future)).plan, 'second');

      container.updateOverrides([
        apiProvider.overrideWithValue(api),
        accountProvider.overrideWithValue(null),
      ]);
      await expectLater(
        container.read(historyProvider.future),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        container.read(allowanceProvider.future),
        throwsA(isA<AppFailure>()),
      );
      expect(api.calls, 4);
    },
  );
}
