begin;
select plan(4);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com');
insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'A'),
  ('22222222-2222-2222-2222-222222222222', 'B');
insert into public.rooms (id, name, invite_code, timezone, created_by) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R1', 'ABCDEF', 'Asia/Taipei', '11111111-1111-1111-1111-111111111111');
insert into public.room_members (room_id, user_id, role, joined_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner',  '2026-09-01 00:00+00'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member', '2026-09-01 01:00+00');

-- 刪除帳號會 cascade 掉 room_members；交接必須照樣發生（P6 的 delete_account() 走的就是這條路）
delete from auth.users where id = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$select user_id from public.room_members
    where room_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and role = 'owner'$$,
  array['22222222-2222-2222-2222-222222222222'::uuid],
  'deleting the owner account promotes the next member');
select is(
  (select abandoned_at from public.rooms where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  null, 'a room with a remaining member is not abandoned');

-- 最後一位成員也被刪除：房間必須標記 abandoned，否則 P6 的清除永遠掃不到它
delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
select is_empty(
  $$select 1 from public.room_members where room_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'no members remain');
select isnt(
  (select abandoned_at from public.rooms where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  null, 'a room emptied by cascade is marked abandoned');

select * from finish();
rollback;
