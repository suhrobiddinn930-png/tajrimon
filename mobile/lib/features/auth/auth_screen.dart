import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'AI Live Translator',
    children: [
      const SizedBox(height: 36),
      Icon(
        Icons.spatial_audio_off_rounded,
        size: 112,
        color: Theme.of(context).colorScheme.primary,
      ),
      Text(
        context.tr('Different languages.\nOne conversation.'),
        style: Theme.of(context).textTheme.displaySmall,
      ),
      Text(
        context.tr(
          'Connect two phones, choose your languages and hear each other through your headphones.',
        ),
      ),
      InfoCard(
        title: context.tr('Your voice, translated by AI'),
        body: context.tr(
          'Speech is sent to an AI provider. The translated voice is AI generated. '
          'This early version translates short turns while the app is open. Audio and transcripts are not saved as history.',
        ),
      ),
      FilledButton(
        onPressed: () => context.go('/login'),
        child: Text(context.tr('Get started')),
      ),
    ],
  );
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool signup = false, busy = false;
  String? notice;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    await runAction(context, () async {
      final auth = ref.read(supabaseProvider).auth;
      if (signup) {
        await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: AppConfig.authRedirect,
        );
        if (mounted) {
          setState(
            () => notice =
                'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: signup ? context.tr('Create account') : context.tr('Welcome back'),
    children: [
      Text(
        context.tr('A world without\nlanguage barriers.'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(labelText: context.tr('Email')),
      ),
      TextField(
        controller: password,
        obscureText: true,
        decoration: InputDecoration(labelText: context.tr('Password')),
      ),
      if (notice != null)
        Text(context.tr(notice!), semanticsLabel: context.tr(notice!)),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(
          busy
              ? context.tr('Please wait…')
              : signup
              ? context.tr('Sign up')
              : context.tr('Sign in'),
        ),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => setState(() {
                signup = !signup;
                notice = null;
              }),
        child: Text(
          signup
              ? context.tr('Already have an account? Sign in')
              : context.tr('Create an account'),
        ),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => runAction(context, () async {
                await ref
                    .read(supabaseProvider)
                    .auth
                    .resetPasswordForEmail(
                      email.text.trim(),
                      redirectTo: AppConfig.authRedirect,
                    );
                if (mounted) {
                  setState(
                    () => notice =
                        'If the account exists, a password reset email has been sent.',
                  );
                }
              }),
        child: Text(context.tr('Forgot password?')),
      ),
    ],
  );
}

class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;
  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  final password = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: context.tr('New password'),
    children: [
      TextField(
        controller: password,
        obscureText: true,
        decoration: InputDecoration(labelText: context.tr('New password')),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                await runAction(context, () async {
                  await ref
                      .read(supabaseProvider)
                      .auth
                      .updateUser(UserAttributes(password: password.text));
                  widget.onComplete();
                });
                if (mounted) setState(() => busy = false);
              },
        child: Text(context.tr('Save password')),
      ),
    ],
  );
}
