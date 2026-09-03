-- 加入嘗試紀錄：只給 join_room 做速率限制用，client 完全不可見
create table public.join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  attempted_at timestamptz not null default now()
);
create index join_attempts_user_time_idx on public.join_attempts (user_id, attempted_at);
alter table public.join_attempts enable row level security;
revoke all on public.join_attempts from anon, authenticated;

-- 與 Swift InviteCode.alphabet 相同
create or replace function public.generate_invite_code() returns text
language plpgsql volatile as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text := '';
begin
  for i in 1..6 loop
    code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return code;
end;
$$;
revoke all on function public.generate_invite_code() from public, anon;

create or replace function public.create_room(p_name text, p_timezone text) returns public.rooms
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_code text;
  v_room public.rooms;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = v_uid) then raise exception 'profile_required'; end if;
  if char_length(v_name) not between 1 and 30 then raise exception 'invalid_name'; end if;
  if not exists (select 1 from pg_timezone_names where name = p_timezone) then raise exception 'invalid_timezone'; end if;

  for attempt in 1..10 loop
    v_code := public.generate_invite_code();
    exit when not exists (select 1 from public.rooms where invite_code = v_code);
    if attempt = 10 then raise exception 'code_generation_failed'; end if;
  end loop;

  insert into public.rooms (name, invite_code, timezone, created_by)
  values (v_name, v_code, p_timezone, v_uid)
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role) values (v_room.id, v_uid, 'owner');
  return v_room;
end;
$$;

-- 錯誤以 jsonb 回傳而非 raise：raise 會回滾 join_attempts 的寫入，讓速率限制失效
create or replace function public.join_room(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[\s\-]', '', 'g'));
  v_recent int;
  v_room public.rooms;
  v_count int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = v_uid) then raise exception 'profile_required'; end if;

  select count(*) into v_recent from public.join_attempts
   where user_id = v_uid and attempted_at > now() - interval '1 minute';
  if v_recent >= 5 then return jsonb_build_object('error', 'rate_limited'); end if;
  insert into public.join_attempts (user_id) values (v_uid);
  delete from public.join_attempts where attempted_at < now() - interval '1 day';

  select * into v_room from public.rooms
   where invite_code = v_code and abandoned_at is null
   for update;
  if not found then return jsonb_build_object('error', 'invalid_code'); end if;

  if exists (select 1 from public.room_members where room_id = v_room.id and user_id = v_uid) then
    return jsonb_build_object('error', 'already_member');
  end if;

  select count(*) into v_count from public.room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then return jsonb_build_object('error', 'room_full'); end if;

  insert into public.room_members (room_id, user_id, role) values (v_room.id, v_uid, 'member');
  return jsonb_build_object('room', to_jsonb(v_room));
end;
$$;

create or replace function public.leave_room(p_room_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_next uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform 1 from public.rooms where id = p_room_id for update;

  select role into v_role from public.room_members where room_id = p_room_id and user_id = v_uid;
  if v_role is null then raise exception 'not_member'; end if;

  delete from public.room_members where room_id = p_room_id and user_id = v_uid;

  if v_role = 'owner' then
    select user_id into v_next from public.room_members
     where room_id = p_room_id
     order by joined_at asc, user_id asc
     limit 1;
    if v_next is not null then
      update public.room_members set role = 'owner' where room_id = p_room_id and user_id = v_next;
    end if;
  end if;

  if not exists (select 1 from public.room_members where room_id = p_room_id) then
    update public.rooms set abandoned_at = now() where id = p_room_id;
  end if;
end;
$$;

-- Supabase 對 public schema 的函式有預設 grant 給 anon，只 revoke from public 是無效的
revoke all on function public.create_room(text, text) from public, anon;
revoke all on function public.join_room(text) from public, anon;
revoke all on function public.leave_room(uuid) from public, anon;
grant execute on function public.create_room(text, text) to authenticated;
grant execute on function public.join_room(text) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
