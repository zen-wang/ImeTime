-- 房間
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 30),
  invite_code text not null unique check (invite_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'),
  timezone text not null,                       -- IANA，用於 04:00 日界
  max_members int not null default 12 check (max_members between 2 and 50),
  -- 帳號刪除後房間與歷史仍在，只是不再知道是誰建立的；擁有權由 room_members.role 追蹤
  created_by uuid references public.profiles (id) on delete set null,
  abandoned_at timestamptz,                     -- 最後一人離開的時間；P6 的 purge 依此清除
  created_at timestamptz not null default now()
);

create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  notifications_muted boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
create index room_members_user_idx on public.room_members (user_id);

-- RLS 用的 helper：security definer 以繞過 room_members 自身的 RLS，避免遞迴
create or replace function public.is_room_member(p_room_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = (select auth.uid())
  );
$$;

create or replace function public.is_room_owner(p_room_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = (select auth.uid()) and role = 'owner'
  );
$$;

create or replace function public.shares_room_with(p_user_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.room_members mine
    join public.room_members theirs on theirs.room_id = mine.room_id
    where mine.user_id = (select auth.uid()) and theirs.user_id = p_user_id
  );
$$;

-- Supabase 對 public schema 的函式有預設 grant 給 anon，只 revoke from public 是無效的
revoke all on function public.is_room_member(uuid) from public, anon;
revoke all on function public.is_room_owner(uuid) from public, anon;
revoke all on function public.shares_room_with(uuid) from public, anon;
grant execute on function public.is_room_member(uuid) to authenticated;
grant execute on function public.is_room_owner(uuid) to authenticated;
grant execute on function public.shares_room_with(uuid) to authenticated;

-- 權限：insert 只能透過 RPC；欄位級 update
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
revoke all on public.rooms from anon, authenticated;
revoke all on public.room_members from anon, authenticated;
grant select on public.rooms to authenticated;
grant update (name) on public.rooms to authenticated;
grant select, delete on public.room_members to authenticated;
grant update (notifications_muted) on public.room_members to authenticated;

create policy "rooms: members read"
  on public.rooms for select to authenticated
  using (public.is_room_member(id));

create policy "rooms: owner updates"
  on public.rooms for update to authenticated
  using (public.is_room_owner(id))
  with check (public.is_room_owner(id));

create policy "room_members: members read"
  on public.room_members for select to authenticated
  using (public.is_room_member(room_id));

create policy "room_members: update own row"
  on public.room_members for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 自己離開請走 leave_room()（會處理 owner 轉移）；這條只給 owner 移除他人
create policy "room_members: owner removes others"
  on public.room_members for delete to authenticated
  using (public.is_room_owner(room_id) and user_id <> (select auth.uid()));

-- profiles：同房間成員可互相看到
drop policy "profiles: read own" on public.profiles;
create policy "profiles: read self and roommates"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.shares_room_with(id));
