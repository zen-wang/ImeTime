-- 交接與 abandoned_at 從 leave_room 移到 trigger，這樣 owner 踢人、以及 P6 delete_account()
-- 的 cascade 刪除也走同一條路，不會留下無主或永遠掃不到的房間。
create or replace function public.room_members_after_delete() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_next uuid;
begin
  -- 先鎖房間列：並行的刪除會在這裡排隊，取得鎖之後才用新的 snapshot 判斷是否已空
  perform 1 from public.rooms where id = old.room_id for update;
  if not found then
    return null;  -- 房間本身被刪掉（cascade），沒有要維護的不變量
  end if;

  if old.role = 'owner' then
    select user_id into v_next from public.room_members
     where room_id = old.room_id
     order by joined_at asc, user_id asc
     limit 1;
    if v_next is not null then
      update public.room_members set role = 'owner'
       where room_id = old.room_id and user_id = v_next;
    end if;
  end if;

  if not exists (select 1 from public.room_members where room_id = old.room_id) then
    update public.rooms set abandoned_at = now()
     where id = old.room_id and abandoned_at is null;
  end if;
  return null;
end;
$$;

revoke all on function public.room_members_after_delete() from public, anon, authenticated;

create trigger room_members_succession
  after delete on public.room_members
  for each row execute function public.room_members_after_delete();

-- leave_room 只負責驗證與刪除；不變量交給 trigger
create or replace function public.leave_room(p_room_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  perform 1 from public.rooms where id = p_room_id for update;

  select role into v_role from public.room_members where room_id = p_room_id and user_id = v_uid;
  if v_role is null then raise exception 'not_member'; end if;

  delete from public.room_members where room_id = p_room_id and user_id = v_uid;
end;
$$;
