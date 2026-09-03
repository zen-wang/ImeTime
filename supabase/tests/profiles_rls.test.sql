begin;
select plan(12);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com');

-- anon 沒有 grant，直接 permission denied
set local role anon;
select throws_ok(
  $$select * from public.profiles$$,
  '42501', null, 'anon cannot read profiles');

-- A 建立、讀取、更新自己的檔案
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$insert into public.profiles (id, display_name)
    values ('11111111-1111-1111-1111-111111111111', '小明') returning display_name$$,
  array['小明'], 'A creates own profile');
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('22222222-2222-2222-2222-222222222222', '冒名')$$,
  '42501', null, 'A cannot create a profile for B');
select results_eq(
  $$select display_name from public.profiles$$,
  array['小明'], 'A reads only own profile');
select results_eq(
  $$update public.profiles set display_name = '小明二號'
    where id = '11111111-1111-1111-1111-111111111111' returning display_name$$,
  array['小明二號'], 'A updates own profile');
select throws_ok(
  $$update public.profiles set created_at = now()
    where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'A cannot rewrite created_at');
select throws_ok(
  $$update public.profiles set id = '22222222-2222-2222-2222-222222222222'
    where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'A cannot reassign own profile to B');
select throws_ok(
  $$delete from public.profiles$$,
  '42501', null, 'authenticated cannot delete profiles');

-- B 看不到、改不到 A
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select is_empty(
  $$select * from public.profiles$$,
  'B reads no profiles (no shared room yet)');
select is_empty(
  $$update public.profiles set display_name = '駭' returning id$$,
  'B updates nothing');

-- check constraints
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('22222222-2222-2222-2222-222222222222', '')$$,
  '23514', null, 'empty display_name rejected');
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('22222222-2222-2222-2222-222222222222', repeat('字', 21))$$,
  '23514', null, '21-char display_name rejected');

select * from finish();
rollback;
