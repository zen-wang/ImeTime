begin;
select plan(4);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com');

-- bucket 設定（以 postgres 身分檢查，不受 RLS 影響）
select results_eq(
  $$select public, file_size_limit::int, allowed_mime_types
    from storage.buckets where id = 'avatars'$$,
  $$values (true, 204800, array['image/jpeg'])$$,
  'avatars bucket is public, 200 KB, jpeg only');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select results_eq(
  $$insert into storage.objects (bucket_id, name)
    values ('avatars', '11111111-1111-1111-1111-111111111111/avatar.jpg') returning name$$,
  array['11111111-1111-1111-1111-111111111111/avatar.jpg'],
  'A uploads into own folder');

select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('avatars', '22222222-2222-2222-2222-222222222222/avatar.jpg')$$,
  '42501', null, 'A cannot upload into another user folder');

select results_eq(
  $$update storage.objects set metadata = '{"touched": true}'::jsonb
    where bucket_id = 'avatars' and name = '11111111-1111-1111-1111-111111111111/avatar.jpg'
    returning name$$,
  array['11111111-1111-1111-1111-111111111111/avatar.jpg'],
  'A updates (upsert) own object');

select * from finish();
rollback;
