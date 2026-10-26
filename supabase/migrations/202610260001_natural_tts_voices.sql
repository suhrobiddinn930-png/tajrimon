alter table public.user_preferences
  drop constraint user_preferences_translation_voice_check;

alter table public.user_preferences
  add constraint user_preferences_translation_voice_check
  check (translation_voice in ('coral','alloy','sage','marin','cedar'));

alter table public.user_preferences
  alter column translation_voice set default 'marin';
