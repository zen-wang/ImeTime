begin;
select plan(7);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'c@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'd@example.com');
insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'A'),
  ('22222222-2222-2222-2222-222222222222', 'B'),
  ('33333333-3333-3333-3333-333333333333', 'C'),
  ('44444444-4444-4444-4444-444444444444', 'D');
insert into public.rooms (id, name, invite_code, timezone, created_by) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R1', 'ABCDEF', 'Asia/Taipei', '11111111-1111-1111-1111-111111111111');
insert into public.room_members (room_id, user_id, role, joined_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner',  '2026-09-01 00:00+00'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member', '2026-09-01 01:00+00'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'member', '2026-09-01 02:00+00');

set local role authenticated;

-- D 不是成員
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok($$select public.leave_room('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$, 'P0001', 'not_member', 'non-member cannot leave');

-- B 離開：A 仍是 owner
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok($$select public.leave_room('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$, 'B leaves');
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$select user_id from public.room_members where role = 'owner'$$,
  array['11111111-1111-1111-1111-111111111111'::uuid], 'A still owner after B leaves');

-- A（owner）離開：最早加入的剩餘成員 C 成為 owner
select lives_ok($$select public.leave_room('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$, 'A leaves');
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select results_eq(
  $$select user_id from public.room_members where role = 'owner'$$,
  array['33333333-3333-3333-3333-333333333333'::uuid], 'C promoted to owner');

-- C 離開：房間標記 abandoned
select lives_ok($$select public.leave_room('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$, 'C leaves');
reset role;
select isnt(
  (select abandoned_at from public.rooms where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  null, 'empty room is marked abandoned');

select * from finish();
rollback;
