import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: context.tr('Plan & usage'),
    children: [
      ref
          .watch(allowanceProvider)
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(context.errorText(e)),
            data: (usage) => InfoCard(
              title: context.tr('{plan} · current plan', {
                'plan': context.tr(switch (usage.plan) {
                  'free' => 'Free',
                  'pro' => 'Pro',
                  'business' => 'Business',
                  _ => usage.plan,
                }),
              }),
              body: context.tr(
                '{used} of {limit} translation minutes used.\n'
                'Estimated AI cost: USD {cost}.\nUTC calendar month. '
                'Each submitted turn is reserved before AI processing, including failed attempts.',
                {
                  'used': (usage.used / 60).toStringAsFixed(1),
                  'limit': '${usage.limit ~/ 60}',
                  'cost': usage.estimatedCost.toStringAsFixed(4),
                },
              ),
            ),
          ),
      for (final plan in [('Free', '10'), ('Pro', '120'), ('Business', '600')])
        InfoCard(
          title: context.tr(plan.$1),
          body: context.tr('{minutes} minutes / month', {'minutes': plan.$2}),
          icon: Icons.bolt_outlined,
        ),
      Text(
        context.tr(
          'Paid checkout is not connected. Pro and Business are server-managed pilot entitlements. '
          'No payment will be taken. Estimates use the operator’s configured rate and are not invoices.',
        ),
      ),
      TextButton(
        onPressed: () => ref.invalidate(allowanceProvider),
        child: Text(context.tr('Refresh usage')),
      ),
    ],
  );
}
