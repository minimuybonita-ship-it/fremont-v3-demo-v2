-- ============================================================
-- 031_household_and_season_status.sql
--
-- (1) Household creation + linking — the MINIMUM workflow families need to onboard.
--     Decision (D5): manual creation of three linked rows per household in the Supabase Table Editor is NOT
--     workable for a non-technical Commissioner, so two narrow functions are provided and nothing more:
--       commissioner_create_household(...)  Commissioner records a household + its guardian email(s).
--       claim_my_household()                On sign-in, a guardian whose VERIFIED login email matches exactly one
--                                           unclaimed guardian row is linked to that household.
--     Fail closed: ambiguous / unverified / already-claimed -> no link, no role.
--     Role assignment for team parents / coaches stays manual (Table Editor or SQL) in V1.
--
-- (2) set_season_status — season status is no longer a free-form client UPDATE (027 revoked it).
--     Enforces: forward-only lifecycle, at most ONE open/active season (the app's contract), a season
--     must have a config before registration opens, and CLOSING requires can_close_season() = ready.
-- ============================================================

create or replace function commissioner_create_household(
  p_display_name text,
  p_guardian_name text,
  p_guardian_email text,
  p_guardian_phone text default null,
  p_guardian2_name text default null,
  p_guardian2_email text default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_family uuid; v_e1 text; v_e2 text;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can create a household'; end if;
  if p_display_name is null or length(btrim(p_display_name)) < 2 then raise exception 'Household name is required'; end if;
  if p_guardian_name is null or length(btrim(p_guardian_name)) < 2 then raise exception 'Guardian name is required'; end if;

  v_e1 := lower(btrim(coalesce(p_guardian_email, '')));
  if v_e1 !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid guardian email is required'; end if;
  if exists (select 1 from guardian where lower(email) = v_e1) then
    raise exception 'That email is already on a household. Use Identity Review instead of creating a duplicate.';
  end if;

  v_e2 := nullif(lower(btrim(coalesce(p_guardian2_email, ''))), '');
  if v_e2 is not null then
    if v_e2 !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Second guardian email is not valid'; end if;
    if v_e2 = v_e1 then raise exception 'Second guardian email must differ from the first'; end if;
    if p_guardian2_name is null or length(btrim(p_guardian2_name)) < 2 then raise exception 'Second guardian name is required'; end if;
    if exists (select 1 from guardian where lower(email) = v_e2) then
      raise exception 'The second guardian''s email is already on a household';
    end if;
  end if;

  insert into family (display_name) values (btrim(p_display_name)) returning id into v_family;
  insert into guardian (family_id, full_name, email, phone, is_primary)
    values (v_family, btrim(p_guardian_name), v_e1, nullif(btrim(coalesce(p_guardian_phone, '')), ''), true);
  if v_e2 is not null then
    insert into guardian (family_id, full_name, email, is_primary) values (v_family, btrim(p_guardian2_name), v_e2, false);
  end if;
  return v_family;
end;
$$;

create or replace function claim_my_household()
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid(); v_email text; v_confirmed timestamptz; v_fams uuid[]; v_fam uuid;
begin
  if v_uid is null then raise exception 'Sign in first'; end if;

  select lower(u.email), u.email_confirmed_at into v_email, v_confirmed from auth.users u where u.id = v_uid;
  if v_email is null or v_confirmed is null then return null; end if;          -- unverified login: never link

  select array_agg(distinct g.family_id) into v_fams
    from guardian g join family f on f.id = g.family_id
    where lower(g.email) = v_email
      and (g.auth_user_id is null or g.auth_user_id = v_uid)
      and f.duplicate_review_status <> 'merged';
  if v_fams is null then return null; end if;                                  -- no household for this email
  if array_length(v_fams, 1) > 1 then
    raise exception 'This email is listed on more than one household. Ask the Commissioner to review it.';
  end if;
  v_fam := v_fams[1];

  update guardian set auth_user_id = v_uid where family_id = v_fam and lower(email) = v_email and auth_user_id is null;
  if not exists (select 1 from app_role where auth_user_id = v_uid and role = 'guardian' and family_id = v_fam) then
    insert into app_role (auth_user_id, role, family_id) values (v_uid, 'guardian', v_fam);
  end if;
  return v_fam;
end;
$$;

create or replace function set_season_status(p_season_id uuid, p_new_status text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_cur text; v_ready boolean; v_reasons text[]; v_other integer;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can change a season''s status'; end if;
  if p_new_status not in ('registration_open', 'active', 'closed') then
    raise exception 'Status must be registration_open, active or closed';
  end if;
  select status into v_cur from season where id = p_season_id for update;
  if v_cur is null then raise exception 'Season not found'; end if;
  if v_cur = p_new_status then return; end if;                                 -- idempotent

  if not ((v_cur = 'planning' and p_new_status = 'registration_open')
       or (v_cur = 'registration_open' and p_new_status in ('active', 'closed'))
       or (v_cur = 'active' and p_new_status = 'closed')) then
    raise exception 'A season cannot move from "%" to "%"', v_cur, p_new_status;
  end if;

  if p_new_status in ('registration_open', 'active') then
    select count(*) into v_other from season where id <> p_season_id and status in ('registration_open', 'active');
    if v_other > 0 then
      raise exception 'Another season is already open or active. Only one season can be open at a time; close it first.';
    end if;
    if p_new_status = 'registration_open' and not exists (select 1 from season_config where season_id = p_season_id) then
      raise exception 'Add the season settings (hours, fundraising goal, fees) before opening registration';
    end if;
  end if;

  if p_new_status = 'closed' then
    select c.ready, c.reasons into v_ready, v_reasons from can_close_season(p_season_id) c;
    if v_ready is distinct from true then
      raise exception 'Season cannot be closed yet: %', array_to_string(coalesce(v_reasons, array['readiness could not be determined']), '; ');
    end if;
  end if;

  update season set status = p_new_status where id = p_season_id;
end;
$$;

revoke execute on function commissioner_create_household(text, text, text, text, text, text), claim_my_household(),
  set_season_status(uuid, text) from public, anon;
grant  execute on function commissioner_create_household(text, text, text, text, text, text), claim_my_household(),
  set_season_status(uuid, text) to authenticated;
