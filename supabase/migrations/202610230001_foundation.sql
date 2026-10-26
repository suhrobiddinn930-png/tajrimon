-- All audio and transcripts remain outside PostgreSQL. Authenticated, non-anonymous users only.
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default 'Translator' check (length(display_name) between 1 and 80),
 preferred_language text not null default 'en' check (preferred_language ~ '^[a-z]{2,3}$'),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.conversations (
 id uuid primary key default gen_random_uuid(),
 join_code_hash text unique,
 created_by uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'waiting' check (status in ('waiting','active','ended')),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now() + interval '1 hour', ended_at timestamptz,
 check (expires_at > created_at)
);
create table public.conversation_participants (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 source_language text not null check (source_language ~ '^[a-z]{2,3}$'),
 target_language text not null check (target_language ~ '^[a-z]{2,3}$'),
 joined_at timestamptz not null default now(), left_at timestamptz,
 connection_status text not null default 'disconnected'
   check (connection_status in ('connected','disconnected')),
 unique (conversation_id,user_id), check (source_language <> target_language)
);
create index participants_user on public.conversation_participants(user_id,joined_at desc);
create table public.usage_records (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 conversation_id uuid references public.conversations(id) on delete set null,
 duration_seconds integer not null check (duration_seconds between 1 and 15),
 provider text not null default 'openai',
 estimated_cost numeric(12,6) not null check (estimated_cost >= 0),
 created_at timestamptz not null default now()
);
create index usage_user_period on public.usage_records(user_id,created_at);
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references public.profiles(id) on delete cascade,
 plan text not null default 'free' check (plan in ('free','pro','business')),
 status text not null default 'active' check (status in ('active','expired','cancelled')),
 current_period_end timestamptz,
 provider_subscription_id text unique,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.user_preferences (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 translation_voice text not null default 'coral' check (translation_voice in ('coral','alloy','sage')),
 auto_play_translation boolean not null default true,
 -- Persistence is deliberately unavailable in this MVP, even with consent.
 save_transcript boolean not null default false check (save_transcript = false),
 preferred_audio_output text not null default 'system' check (preferred_audio_output = 'system'),
 updated_at timestamptz not null default now()
);
create function public.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger subscriptions_touch before update on public.subscriptions for each row execute function public.touch_updated_at();
create trigger preferences_touch before update on public.user_preferences for each row execute function public.touch_updated_at();

create function public.bootstrap_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id) values (new.id);
 insert into public.user_preferences(user_id) values (new.id);
 insert into public.subscriptions(user_id) values (new.id);
 return new;
end $$;
create trigger bootstrap_user after insert on auth.users for each row execute function public.bootstrap_user();

create function public.is_member(room uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.conversation_participants
 where conversation_id = room and user_id = auth.uid() and left_at is null)
 and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
$$;
alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.usage_records enable row level security;
alter table public.subscriptions enable row level security;
alter table public.user_preferences enable row level security;

create policy profile_read on public.profiles for select to authenticated using (id=auth.uid());
create policy profile_update on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
-- Historical members can see room metadata; live endpoints separately require active membership.
create function public.was_member(room uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.conversation_participants where conversation_id=room and user_id=auth.uid())
$$;
create policy room_read on public.conversations for select to authenticated using (public.was_member(id));
create policy participant_read on public.conversation_participants for select to authenticated using (public.was_member(conversation_id));
create policy usage_read on public.usage_records for select to authenticated using (user_id=auth.uid());
create policy subscription_read on public.subscriptions for select to authenticated using (user_id=auth.uid());
create policy preferences_read on public.user_preferences for select to authenticated using (user_id=auth.uid());
create policy preferences_update on public.user_preferences for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

revoke all on public.profiles, public.conversations, public.conversation_participants,
 public.usage_records, public.subscriptions, public.user_preferences from anon, authenticated;
grant select on public.profiles, public.conversations, public.conversation_participants,
 public.usage_records, public.subscriptions, public.user_preferences to authenticated;
grant update(display_name,preferred_language) on public.profiles to authenticated;
grant update(translation_voice,auto_play_translation,save_transcript,preferred_audio_output) on public.user_preferences to authenticated;
-- Join hashes are not exposed to mobile users, including the room owner.
revoke select on public.conversations from authenticated;
grant select(id,created_by,status,created_at,expires_at,ended_at) on public.conversations to authenticated;
grant all on public.profiles,public.conversations,public.conversation_participants,
 public.usage_records,public.subscriptions,public.user_preferences to service_role;

-- Enforce capacity even for accidental trusted-server direct writes. Lock the parent row.
create function public.enforce_capacity() returns trigger language plpgsql set search_path = '' as $$
begin
 perform 1 from public.conversations where id=new.conversation_id for update;
 if new.left_at is null and (select count(*) from public.conversation_participants
    where conversation_id=new.conversation_id and left_at is null and id<>new.id) >= 2 then
   raise exception 'room_full';
 end if;
 return new;
end $$;
create trigger participant_capacity before insert or update on public.conversation_participants
for each row execute function public.enforce_capacity();

create function public.create_room(p_user uuid,p_hash text,p_source text,p_target text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare room uuid;
begin
 insert into public.conversations(created_by,join_code_hash) values(p_user,p_hash) returning id into room;
 insert into public.conversation_participants(conversation_id,user_id,source_language,target_language)
 values(room,p_user,p_source,p_target);
 return room;
end $$;

create function public.join_room(p_user uuid,p_hash text,p_source text,p_target text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare room public.conversations; host public.conversation_participants;
begin
 select * into room from public.conversations where join_code_hash=p_hash for update;
 if not found or room.expires_at <= now() or room.status <> 'waiting' then raise exception 'invalid_room'; end if;
 select * into host from public.conversation_participants where conversation_id=room.id and left_at is null;
 if host.user_id=p_user then raise exception 'already_joined'; end if;
 if host.source_language<>p_target or host.target_language<>p_source then raise exception 'language_mismatch'; end if;
 insert into public.conversation_participants(conversation_id,user_id,source_language,target_language)
 values(room.id,p_user,p_source,p_target);
 -- Code is single use. Once admitted, authentication + membership govern access.
 update public.conversations set status='active',join_code_hash=null where id=room.id;
 return room.id;
end $$;

create function public.close_room(p_user uuid,p_room uuid,p_owner_only boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare room public.conversations;
begin
 select * into room from public.conversations where id=p_room for update;
 if not found or not exists(select 1 from public.conversation_participants
 where conversation_id=p_room and user_id=p_user and left_at is null) then raise exception 'forbidden'; end if;
 if p_owner_only and room.created_by<>p_user then raise exception 'forbidden'; end if;
 update public.conversations set status='ended',ended_at=now(),join_code_hash=null where id=p_room;
 -- A two-person room ends when either person leaves.
 update public.conversation_participants set left_at=now(),connection_status='disconnected' where conversation_id=p_room and left_at is null;
end $$;

create function public.reserve_usage(p_user uuid,p_room uuid,p_seconds integer,p_cost numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare sub public.subscriptions; used bigint; quota integer; record_id uuid;
begin
 if p_seconds not between 1 and 15 or p_cost<0 then raise exception 'invalid_usage'; end if;
 -- Room lock coordinates expiry/end/join; subscription lock serializes all user reservations.
 perform 1 from public.conversations where id=p_room and status='active' and expires_at>now() for update;
 if not found or not exists(select 1 from public.conversation_participants where conversation_id=p_room and user_id=p_user and left_at is null) then raise exception 'forbidden'; end if;
 select * into sub from public.subscriptions where user_id=p_user for update;
 if not found then raise exception 'quota_exceeded'; end if;
 quota := case when sub.status='active' and (sub.plan='free' or sub.current_period_end>now())
 then case sub.plan when 'business' then 36000 when 'pro' then 7200 else 600 end else 600 end;
 select coalesce(sum(duration_seconds),0) into used from public.usage_records
 where user_id=p_user and created_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
 if used+p_seconds>quota then raise exception 'quota_exceeded'; end if;
 insert into public.usage_records(user_id,conversation_id,duration_seconds,estimated_cost)
 values(p_user,p_room,p_seconds,p_cost) returning id into record_id;
 return record_id;
end $$;

-- PostgreSQL functions default to PUBLIC execute. Explicitly revoke every privileged RPC.
revoke all on function public.create_room(uuid,text,text,text),public.join_room(uuid,text,text,text),
 public.close_room(uuid,uuid,boolean),public.reserve_usage(uuid,uuid,integer,numeric),
 public.bootstrap_user(),public.enforce_capacity(),public.touch_updated_at() from public,anon,authenticated;
grant execute on function public.create_room(uuid,text,text,text),public.join_room(uuid,text,text,text),
 public.close_room(uuid,uuid,boolean),public.reserve_usage(uuid,uuid,integer,numeric) to service_role;
revoke all on function public.is_member(uuid),public.was_member(uuid) from public,anon;
grant execute on function public.is_member(uuid),public.was_member(uuid) to authenticated,service_role;

-- Audio never traverses Realtime. Membership/status metadata only.
alter publication supabase_realtime add table public.conversations,public.conversation_participants;
