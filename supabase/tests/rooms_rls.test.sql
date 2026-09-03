begin;
select plan(14);

-- 三個使用者：A（owner）、B（member）、C（不在房間）
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'c@example.com');
insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'A'),
  ('22222222-2222-2222-2222-222222222222', 'B'),
  ('33333333-3333-3333-3333-333333333333', 'C');
insert into public.rooms (id, name, invite_code, timezone, created_by) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R1', 'ABCDEF', 'Asia/Taipei', '11111111-1111-1111-1111-111111111111');
insert into public.room_members (room_id, user_id, role) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member');

-- anon
set local role anon;
select throws_ok($$select * from public.rooms$$, '42501', null, 'anon cannot read rooms');

-- A（owner）
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq($$select name from public.rooms$$, array['R1'], 'A reads own room');
select throws_ok(
  $$insert into public.rooms (name, invite_code, timezone, created_by)
    values ('X', 'ZZZZZZ', 'Asia/Taipei', '11111111-1111-1111-1111-111111111111')$$,
  '42501', null, 'members cannot insert rooms directly');
select throws_ok(
  $$insert into public.room_members (room_id, user_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  '42501', null, 'members cannot insert memberships directly');
select results_eq(
  $$update public.rooms set name = 'R1 改名' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' returning name$$,
  array['R1 改名'], 'owner renames room');
select throws_ok(
  $$update public.rooms set max_members = 50 where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', null, 'nobody can change max_members from the client');
select results_eq(
  $$select display_name from public.profiles where id = '22222222-2222-2222-2222-222222222222'$$,
  array['B'], 'A reads roommate B profile');
select is_empty(
  $$select * from public.profiles where id = '33333333-3333-3333-3333-333333333333'$$,
  'A cannot read stranger C profile');

-- B（member）
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select is_empty(
  $$update public.rooms set name = 'B 亂改' returning id$$,
  'member cannot rename room');
select results_eq(
  $$update public.room_members set notifications_muted = true
    where room_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and user_id = '22222222-2222-2222-2222-222222222222'
    returning notifications_muted$$,
  array[true], 'B mutes own membership');
select is_empty(
  $$update public.room_members set notifications_muted = true
    where user_id = '11111111-1111-1111-1111-111111111111' returning user_id$$,
  'B cannot mute A');
select is_empty(
  $$delete from public.room_members where user_id = '11111111-1111-1111-1111-111111111111' returning user_id$$,
  'member cannot remove owner');

-- C（外人）
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select is_empty($$select * from public.rooms$$, 'stranger reads no rooms');

-- A 移除 B
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$delete from public.room_members where user_id = '22222222-2222-2222-2222-222222222222' returning user_id$$,
  array['22222222-2222-2222-2222-222222222222'::uuid], 'owner removes member');

select * from finish();
rollback;
