begin;
select plan(7);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'noprofile@example.com');
insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'A');

set local role anon;
select throws_ok($$select public.create_room('X', 'Asia/Taipei')$$, '42501', null, 'anon cannot call create_room');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$select name from public.create_room('  週末小隊 ', 'Asia/Taipei')$$,
  array['週末小隊'], 'creates room with trimmed name');
select results_eq(
  $$select role from public.room_members where user_id = '11111111-1111-1111-1111-111111111111'$$,
  array['owner'], 'creator becomes owner');
select ok(
  (select invite_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' from public.rooms limit 1),
  'invite code uses the 32-letter alphabet');
select throws_ok($$select public.create_room('   ', 'Asia/Taipei')$$, 'P0001', 'invalid_name', 'blank name rejected');
select throws_ok($$select public.create_room('X', 'Mars/Olympus')$$, 'P0001', 'invalid_timezone', 'unknown timezone rejected');

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok($$select public.create_room('X', 'Asia/Taipei')$$, 'P0001', 'profile_required', 'user without profile cannot create');

select * from finish();
rollback;
