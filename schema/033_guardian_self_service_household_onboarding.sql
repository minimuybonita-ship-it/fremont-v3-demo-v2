-- ============================================================
-- 033_guardian_self_service_household_onboarding.sql
-- Verified guardians can create a family profile when no existing
-- household/role matches their email. Existing identities fail closed.
-- ============================================================
create or replace function create_my_household(
  p_display_name text,
  p_guardian_name text,
  p_guardian_phone text default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_confirmed timestamptz;
  v_family uuid;
  v_existing_count integer;
begin
  if v_uid is null then raise exception 'Sign in first'; end if;
  select lower(u.email), u.email_confirmed_at into v_email, v_confirmed
    from auth.users u where u.id = v_uid;
  if v_email is null or v_confirmed is null then raise exception 'Verify your email before creating a family profile'; end if;
  if p_display_name is null or length(btrim(p_display_name)) < 2 then raise exception 'Family name is required'; end if;
  if p_guardian_name is null or length(btrim(p_guardian_name)) < 2 then raise exception 'Guardian name is required'; end if;
  if exists (select 1 from app_role where auth_user_id = v_uid) then
    raise exception 'This account is already linked. Refresh and sign in again.';
  end if;
  select count(*) into v_existing_count
    from guardian g join family f on f.id = g.family_id
    where lower(g.email) = v_email and f.duplicate_review_status <> 'merged';
  if v_existing_count > 0 then
    raise exception 'A family profile already exists for this email. Use the existing profile or ask the Commissioner to review it.';
  end if;
  insert into family (display_name) values (btrim(p_display_name)) returning id into v_family;
  insert into guardian (family_id, auth_user_id, full_name, email, phone, is_primary)
    values (v_family, v_uid, btrim(p_guardian_name), v_email, nullif(btrim(coalesce(p_guardian_phone, '')), ''), true);
  insert into app_role (auth_user_id, role, family_id) values (v_uid, 'guardian', v_family);
  return v_family;
end;
$$;
revoke execute on function create_my_household(text, text, text) from public, anon;
grant execute on function create_my_household(text, text, text) to authenticated;
