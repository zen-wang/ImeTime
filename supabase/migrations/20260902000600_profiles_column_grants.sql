-- created_at 是稽核欄位，不該由客戶端改寫；只開放使用者真正會編輯的兩欄
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_path) on public.profiles to authenticated;
