begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'c@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'noprofile@example.com');
insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'A'),
  ('22222222-2222-2222-2222-222222222222', 'B'),
  ('33333333-3333-3333-3333-333333333333', 'C');
-- 上限 2 人的房間，A 已在裡面
insert into public.rooms (id, name, invite_code, timezone, max_members, created_by) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R1', 'ABCDEF', 'Asia/Taipei', 2, '11111111-1111-1111-1111-111111111111');
insert into public.room_members (room_id, user_id, role) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner');

set local role authenticated;

-- B：正規化後加入成功
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$select ((public.join_room(' abc def '))->'room'->>'id')::uuid$$,
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid], 'B joins with lowercase/spaced code');
select results_eq(
  $$select (public.join_room('ABCDEF'))->>'error'$$,
  array['already_member'], 'B cannot join twice');
select results_eq(
  $$select count(*)::int from public.room_members where room_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array[2], 'room now has 2 members');

-- C：滿了、錯碼、速率限制（同一交易內 now() 固定，5 次後第 6 次被擋）
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select results_eq($$select (public.join_room('ABCDEF'))->>'error'$$, array['room_full'], 'C gets room_full');
select results_eq($$select (public.join_room('ZZZZZZ'))->>'error'$$, array['invalid_code'], 'C gets invalid_code');
select results_eq(
  $$select (public.join_room('ZZZZZZ'))->>'error' from generate_series(1, 3)$$,
  array['invalid_code', 'invalid_code', 'invalid_code'], 'attempts 3-5 still evaluated');
select results_eq($$select (public.join_room('ABCDEF'))->>'error'$$, array['rate_limited'], '6th attempt in a minute is rate limited');

-- 沒有 profile 的使用者
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok($$select public.join_room('ABCDEF')$$, 'P0001', 'profile_required', 'user without profile cannot join');

-- anon
set local role anon;
select throws_ok($$select public.join_room('ABCDEF')$$, '42501', null, 'anon cannot call join_room');

select * from finish();
rollback;
