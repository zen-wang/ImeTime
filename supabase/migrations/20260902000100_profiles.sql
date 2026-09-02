-- profiles：1:1 對應 auth.users，由 App 在首次登入後建立（不用 trigger，讓使用者先填名稱）
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  avatar_path text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Supabase 預設會把 public schema 的表 grant 給 anon/authenticated；收回 anon
revoke all on public.profiles from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;

create policy "profiles: read own"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: insert own"
  on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- 不開 delete：刪除走 P6 的 delete_account()
