import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final name = TextEditingController();
  String language = 'en', voice = 'marin';
  bool autoplay = true, loaded = false, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await runAction(context, () async {
      final db = ref.read(supabaseProvider);
      final uid = db.auth.currentUser!.id;
      final profile = await db.from('profiles').select().eq('id', uid).single();
      final pref = await db
          .from('user_preferences')
          .select()
          .eq('user_id', uid)
          .single();
      if (mounted) {
        setState(() {
          name.text = profile['display_name'] as String;
          language = profile['preferred_language'] as String;
          voice = pref['translation_voice'] as String;
          autoplay = pref['auto_play_translation'] as bool;
          loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    await runAction(context, () async {
      final db = ref.read(supabaseProvider);
      final uid = db.auth.currentUser!.id;
      await db
          .from('profiles')
          .update({
            'display_name': name.text.trim(),
            'preferred_language': language,
          })
          .eq('id', uid);
      await db
          .from('user_preferences')
          .update({
            'translation_voice': voice,
            'auto_play_translation': autoplay,
          })
          .eq('user_id', uid);
      ref.read(languagePairProvider.notifier).state = (
        language,
        language == 'en' ? 'de' : 'en',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Preferences saved.'))),
        );
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: context.tr('Profile & privacy'),
    children: [
      if (!loaded)
        TextButton(onPressed: load, child: Text(context.tr('Load profile'))),
      TextField(
        controller: name,
        maxLength: 80,
        decoration: InputDecoration(labelText: context.tr('Display name')),
      ),
      DropdownButtonFormField(
        initialValue: language,
        decoration: InputDecoration(
          labelText: context.tr('Preferred language'),
        ),
        items: languageNames.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(context.languageName(e.key)),
              ),
            )
            .toList(),
        onChanged: (String? value) =>
            setState(() => language = value ?? language),
      ),
      DropdownButtonFormField(
        initialValue: voice,
        decoration: InputDecoration(
          labelText: context.tr('Translated AI voice'),
        ),
        items: [
          'marin',
          'cedar',
          'coral',
          'alloy',
          'sage',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (String? value) => setState(() => voice = value ?? voice),
      ),
      Text(
        context.tr(
          'Marin and Cedar are the recommended natural-sounding options. '
          'The voice is AI-generated, and quality varies by language.',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('Automatically play translations')),
        value: autoplay,
        onChanged: (value) => setState(() => autoplay = value),
      ),
      DropdownButtonFormField(
        initialValue: ref.watch(themeModeProvider),
        decoration: InputDecoration(labelText: context.tr('Appearance')),
        items: ThemeMode.values
            .map(
              (m) =>
                  DropdownMenuItem(value: m, child: Text(context.tr(m.name))),
            )
            .toList(),
        onChanged: (ThemeMode? m) {
          if (m != null) ref.read(themeModeProvider.notifier).state = m;
        },
      ),
      InfoCard(
        title: context.tr('Temporary speech processing'),
        body: context.tr(
          'Audio and transcripts are held temporarily during translation and sent to the configured AI provider. '
          'This MVP does not offer saved transcripts. Provider retention follows your API account’s data controls. '
          'Leaving the live screen clears its transcript. Display name and language pair are shared with your room partner.',
        ),
      ),
      FilledButton(
        onPressed: loaded && !busy ? save : null,
        child: Text(context.tr('Save preferences')),
      ),
      OutlinedButton(
        onPressed: () =>
            runAction(context, () => ref.read(supabaseProvider).auth.signOut()),
        child: Text(context.tr('Sign out')),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(context.tr('Delete your account?')),
                    content: Text(
                      context.tr(
                        'This permanently deletes your profile, preferences, usage and rooms you created.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.tr('Cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(context.tr('Delete account')),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                setState(() => busy = true);
                await runAction(context, () async {
                  await ref.read(apiProvider).request('DELETE', '/account');
                  await ref.read(supabaseProvider).auth.signOut();
                });
                if (mounted) setState(() => busy = false);
              },
        child: Text(context.tr('Delete account and data')),
      ),
    ],
  );
}
