-- SAHM online community schema for Supabase
-- Run this entire script in Supabase Dashboard -> SQL Editor.
-- This schema stores only public profile fields, follower links, friendships and chat messages.
-- Email addresses and passwords are never exposed through public.profiles.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null default 'SAHM user',
  bio text not null default '',
  avatar_url text,
  created_at timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_.]{3,20}$')
);
create unique index if not exists profiles_username_lower_unique on public.profiles (lower(username));

create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self_follow check (follower_id <> following_id)
);
create index if not exists follows_following_idx on public.follows (following_id);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  constraint friendships_no_self_friend check (user_id <> friend_id)
);
create index if not exists friendships_friend_idx on public.friendships (friend_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  constraint messages_no_self_message check (sender_id <> receiver_id)
);
create index if not exists messages_conversation_idx on public.messages (sender_id, receiver_id, created_at);
create index if not exists messages_receiver_idx on public.messages (receiver_id, created_at);

-- Create a public-facing profile row when an email account is registered.
-- If the selected username is already taken (for example, a simultaneous sign-up),
-- use a unique fallback so the account can still be created and the user can edit it later.
create or replace function public.handle_new_sahm_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_username text;
  final_username text;
  requested_name text;
begin
  requested_username := lower(coalesce(new.raw_user_meta_data ->> 'username', ''));
  requested_name := left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'SAHM user'), '@', 1)), 60);

  if requested_username !~ '^[a-z0-9_.]{3,20}$'
     or exists (select 1 from public.profiles p where lower(p.username) = requested_username) then
    final_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 12);
  else
    final_username := requested_username;
  end if;

  insert into public.profiles (id, username, display_name)
  values (new.id, final_username, requested_name)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_sahm_profile on auth.users;
create trigger on_auth_user_created_sahm_profile
after insert on auth.users
for each row execute function public.handle_new_sahm_user();

-- Safe username availability check. It returns a boolean and reveals no account email or profile data.
create or replace function public.is_username_available(requested_username text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(lower(trim(requested_username)) ~ '^[a-z0-9_.]{3,20}$', false)
     and not exists (
       select 1 from public.profiles p
       where lower(p.username) = lower(trim(requested_username))
     );
$$;

grant execute on function public.is_username_available(text) to anon, authenticated;

-- Directory search returns only public profile fields and counts. It never returns email addresses.
create or replace function public.search_profiles(search_term text default null)
returns table (
  id uuid,
  username text,
  display_name text,
  bio text,
  avatar_url text,
  created_at timestamptz,
  followers_count bigint,
  following_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.bio, p.avatar_url, p.created_at,
         (select count(*) from public.follows f where f.following_id = p.id) as followers_count,
         (select count(*) from public.follows f where f.follower_id = p.id) as following_count
  from public.profiles p
  where auth.uid() is not null
    and (
      search_term is null or btrim(search_term) = ''
      or p.username ilike '%' || btrim(search_term) || '%'
      or p.display_name ilike '%' || btrim(search_term) || '%'
    )
  order by p.created_at desc
  limit 150;
$$;

grant execute on function public.search_profiles(text) to authenticated;

-- Turn on row-level security everywhere the browser can access data.
alter table public.profiles enable row level security;
alter table public.follows enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;

-- Recreate policies safely if this script is run again.
drop policy if exists "Authenticated users can view public profiles" on public.profiles;
drop policy if exists "Users can insert their own profile" on public.profiles;
drop policy if exists "Users can update their own profile" on public.profiles;
drop policy if exists "Users can read follows involving themselves" on public.follows;
drop policy if exists "Users can follow as themselves" on public.follows;
drop policy if exists "Users can unfollow as themselves" on public.follows;
drop policy if exists "Users can read friendships involving themselves" on public.friendships;
drop policy if exists "Users can add themselves as friend" on public.friendships;
drop policy if exists "Users can remove friendships they created" on public.friendships;
drop policy if exists "Friends can read their conversation messages" on public.messages;
drop policy if exists "Friends can send messages as themselves" on public.messages;

create policy "Authenticated users can view public profiles"
on public.profiles for select to authenticated
using (true);

create policy "Users can insert their own profile"
on public.profiles for insert to authenticated
with check (id = (select auth.uid()));

create policy "Users can update their own profile"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Users can read follows involving themselves"
on public.follows for select to authenticated
using (follower_id = (select auth.uid()) or following_id = (select auth.uid()));

create policy "Users can follow as themselves"
on public.follows for insert to authenticated
with check (follower_id = (select auth.uid()) and follower_id <> following_id);

create policy "Users can unfollow as themselves"
on public.follows for delete to authenticated
using (follower_id = (select auth.uid()));

create policy "Users can read friendships involving themselves"
on public.friendships for select to authenticated
using (user_id = (select auth.uid()) or friend_id = (select auth.uid()));

create policy "Users can add themselves as friend"
on public.friendships for insert to authenticated
with check (user_id = (select auth.uid()) and user_id <> friend_id);

create policy "Users can remove friendships they created"
on public.friendships for delete to authenticated
using (user_id = (select auth.uid()));

create policy "Friends can read their conversation messages"
on public.messages for select to authenticated
using (
  (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()))
  and exists (
    select 1 from public.friendships f
    where (f.user_id = public.messages.sender_id and f.friend_id = public.messages.receiver_id)
       or (f.user_id = public.messages.receiver_id and f.friend_id = public.messages.sender_id)
  )
);

create policy "Friends can send messages as themselves"
on public.messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and sender_id <> receiver_id
  and char_length(trim(body)) between 1 and 2000
  and exists (
    select 1 from public.friendships f
    where (f.user_id = public.messages.sender_id and f.friend_id = public.messages.receiver_id)
       or (f.user_id = public.messages.receiver_id and f.friend_id = public.messages.sender_id)
  )
);

-- Minimum Data API grants for the browser client. RLS still enforces every row access.
grant select, insert, update on public.profiles to authenticated;
grant select, insert, delete on public.follows to authenticated;
grant select, insert, delete on public.friendships to authenticated;
grant select, insert on public.messages to authenticated;
revoke all on public.profiles from anon;
revoke all on public.follows from anon;
revoke all on public.friendships from anon;
revoke all on public.messages from anon;

-- Enable realtime message delivery. This safely skips the addition if already configured.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
     ) then
    alter publication supabase_realtime add table public.messages;
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'follows') then
    alter publication supabase_realtime add table public.follows;
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'friendships') then
    alter publication supabase_realtime add table public.friendships;
  end if;
end;
$$;
