-- QA SUITE A: per-role access + end-to-end workflows. STAGING ONLY (xyhtaufdyyokjvzctums).
-- RESULT OF LAST RUN (2026-10-21): total=213 pass=213 fail=0.
-- Runs as ONE statement that ends in a forced RAISE EXCEPTION, so nothing persists; results come back in the error text.
-- Role impersonation: set_config('request.jwt.claims', ...) + SET LOCAL ROLE authenticated|anon.
-- Fixture UUIDs (a001..a006, b001, c001, c002, e0xx, f001..f005) are the staging demo fixtures.
-- NOTE: seeded staging data includes one $25 replacement_pool credit for household A (Oct 12 rehearsal), so
--       credit checks are keyed by source_reference_id or expect 26 for household A.
-- Assertion groups (area): anon, norole, family, team, platform, commissioner, household, minutes, registration,
--   selection, phaseB, gameday, noshow, replacement, share, cash, season, mig025, reports.

create temp table results (n serial, area text, name text, expect text, actual text, pass boolean);

create or replace function pg_temp.t(p_area text, p_name text, p_uid text, p_sql text, p_expect text) returns void
language plpgsql as $$
declare v_err text; v_n bigint := 0; v_j text; v_jn text; v_pass boolean; v_actual text; v_sel boolean := p_sql ~* '^\s*select';
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{"role":"anon"}' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute case when p_uid is null then 'set local role anon' else 'set local role authenticated' end;
  begin
    if v_sel then
      execute 'select count(*), (array_agg(to_jsonb(x)::text))[1] from (' || p_sql || ') x' into v_n, v_j;
    else
      execute p_sql; get diagnostics v_n = row_count;
    end if;
  exception when others then v_err := sqlerrm;
  end;
  reset role;
  v_jn := regexp_replace(coalesce(v_j, ''), '":\s+', '":', 'g');
  v_actual := case when v_err is not null then 'error: ' || left(v_err, 120)
                   when v_sel then 'rows=' || v_n || ' ' || left(v_jn, 500)
                   else 'affected=' || v_n end;
  v_pass := case
    when p_expect = 'ok' then v_err is null
    when p_expect = 'error' then v_err is not null
    when p_expect like 'error~%' then v_err ilike '%' || substr(p_expect, 8) || '%'
    when p_expect like 'rows=%' then v_err is null and v_n = substr(p_expect, 6)::bigint
    when p_expect like 'affected=%' then v_err is null and v_n = substr(p_expect, 10)::bigint
    when p_expect like 'has=%' then v_err is null and v_jn like '%' || substr(p_expect, 5) || '%'
    else false end;
  insert into results(area, name, expect, actual, pass) values (p_area, p_name, p_expect, v_actual, v_pass);
end $$;

create or replace function pg_temp.v(p_uid text, p_sql text) returns text
language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
  execute 'select (' || p_sql || ')::text' into r;
  reset role;
  return r;
end $$;

create or replace function pg_temp.chk(p_area text, p_name text, p_expect text, p_actual text) returns void
language plpgsql as $$ begin
  insert into results(area, name, expect, actual, pass) values (p_area, p_name, p_expect, p_actual, p_expect = p_actual); end $$;

do $$
declare
  COMM text := '00000000-0000-0000-0000-00000000a004'; FA text := '00000000-0000-0000-0000-00000000a001';
  FB text := '00000000-0000-0000-0000-00000000a002';   TP1 text := '00000000-0000-0000-0000-00000000a003';
  CO2 text := '00000000-0000-0000-0000-00000000a006';  PO text := '00000000-0000-0000-0000-00000000a005';
  NOR text := '00000000-0000-0000-0000-00000000f001';  AB text := '00000000-0000-0000-0000-00000000f002';
  UNC text := '00000000-0000-0000-0000-00000000f003';  NEWF text := '00000000-0000-0000-0000-00000000f004';
  AMB text := '00000000-0000-0000-0000-00000000f005';
  DEMO uuid := '00000000-0000-0000-0000-00000000b001'; LEG uuid := 'd4664f33-c34f-4837-8194-9daf9ad5976e';
  FAM_A uuid := '00000000-0000-0000-0000-00000000c001'; FAM_B uuid := '00000000-0000-0000-0000-00000000c002';
  FAM_AB uuid := '5c9ad1b7-dfb8-4813-ac7e-d17547fc5750';
  JI_NOW uuid := '00000000-0000-0000-0000-00000000e032'; JI_FUT uuid := '00000000-0000-0000-0000-00000000e034';
  JI_SNACK uuid := '00000000-0000-0000-0000-00000000e035'; JI_CHAIN uuid := '00000000-0000-0000-0000-00000000e036';
  GM_FUT uuid := '00000000-0000-0000-0000-00000000e023'; GM_NOW uuid := '00000000-0000-0000-0000-00000000e022';
  v_fam uuid; v_a uuid; v_b uuid; v_e uuid; v_ns uuid; v_ps uuid; v_pl uuid; v_sub uuid; v_sub2 uuid;
  v_x uuid; v_cfg_leg uuid; v_cfg_demo uuid; v_cash bigint; v_t2 uuid; v_tmp uuid; v_k uuid; v_txt text;
begin
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
    (NOR::uuid, 'norole@example.test', now(), 'authenticated', 'authenticated'),
    (AB::uuid,  'alexben.demo@example.test', now(), 'authenticated', 'authenticated'),
    (UNC::uuid, 'unverified.demo@example.test', null, 'authenticated', 'authenticated'),
    (NEWF::uuid,'newfam.demo@example.test', now(), 'authenticated', 'authenticated'),
    (AMB::uuid, 'ambig.demo@example.test', now(), 'authenticated', 'authenticated');
  select count(*) into v_cash from fundraising_cash_ledger;
  select id into v_cfg_leg from season_config where season_id = LEG order by effective_at desc limit 1;
  select id into v_cfg_demo from season_config where season_id = DEMO order by effective_at desc limit 1;

  -- 1 ANONYMOUS
  perform pg_temp.t('anon','select season',null,'select * from season','error');
  perform pg_temp.t('anon','select family',null,'select * from family','error');
  perform pg_temp.t('anon','select app_role',null,'select * from app_role','error');
  perform pg_temp.t('anon','rpc auth_is_commissioner',null,'select auth_is_commissioner()','error');
  perform pg_temp.t('anon','rpc auth_family_ids',null,'select auth_family_ids()','error');
  perform pg_temp.t('anon','rpc claim_my_household',null,'select claim_my_household()','error');
  perform pg_temp.t('anon','rpc open_jobs_for_season',null,format('select * from open_jobs_for_season(%L)',DEMO),'error');
  perform pg_temp.t('anon','rpc record_cash_entry',null,format('select record_cash_entry(%L, 5)',(select id from player_season limit 1)),'error');
  perform pg_temp.t('anon','insert assignment',null,format('insert into assignment(job_instance_id,family_id) values (%L,%L)',JI_FUT,FAM_A),'error');
  perform pg_temp.t('anon','rpc season_closeout_summary',null,format('select * from season_closeout_summary(%L)',DEMO),'error');

  -- 2 SIGNED IN, NO ROLE
  perform pg_temp.t('norole','family rows=0',NOR,'select * from family','rows=0');
  perform pg_temp.t('norole','player rows=0',NOR,'select * from player','rows=0');
  perform pg_temp.t('norole','assignment rows=0',NOR,'select * from assignment','rows=0');
  perform pg_temp.t('norole','app_role rows=0',NOR,'select * from app_role','rows=0');
  perform pg_temp.t('norole','cash ledger rows=0',NOR,'select * from fundraising_cash_ledger','rows=0');
  perform pg_temp.t('norole','open jobs refused',NOR,format('select * from open_jobs_for_season(%L)',DEMO),'error~not linked');
  perform pg_temp.t('norole','closeout refused',NOR,format('select * from season_closeout_summary(%L)',DEMO),'error~Commissioner');
  perform pg_temp.t('norole','apply auto refused',NOR,format('select * from apply_auto_assignments(%L,''[]'')',DEMO),'error~Commissioner');
  perform pg_temp.t('norole','claim job refused',NOR,format('select claim_volunteer_job(%L)',JI_FUT),'error~not linked');

  -- 3 FAMILY (guardian A)
  perform pg_temp.t('family','sees own family only',FA,'select * from family','rows=1');
  perform pg_temp.t('family','sees own child only',FA,'select * from player','rows=1');
  perform pg_temp.t('family','cannot see family B child',FA,'select * from player where full_name like ''Player B%''','rows=0');
  perform pg_temp.t('family','sees own assignment only',FA,'select * from assignment','rows=1');
  perform pg_temp.t('family','own app_role only',FA,'select * from app_role','rows=1');
  perform pg_temp.t('family','cash ledger hidden',FA,'select * from fundraising_cash_ledger','rows=0');
  perform pg_temp.t('family','direct insert assignment refused',FA,format('insert into assignment(job_instance_id,family_id) values (%L,%L)',JI_FUT,FAM_A),'error');
  perform pg_temp.t('family','direct self-award minutes refused',FA,'update assignment set actual_minutes_worked=9999','error');
  perform pg_temp.t('family','direct status change refused',FA,'update assignment set status=''verified''','error');
  perform pg_temp.t('family','forge audit row refused',FA,format('insert into assignment_audit_log(assignment_id,to_status) values (%L,''verified'')','00000000-0000-0000-0000-00000000e041'),'error');
  perform pg_temp.t('family','forge credit refused',FA,format('insert into fundraising_credit_ledger(family_id,source,amount) values (%L,''admin_adjustment'',500)',FAM_A),'error');
  perform pg_temp.t('family','forge cash refused',FA,format('insert into fundraising_cash_ledger(player_season_id,amount) values (%L,500)',(select id from player_season limit 1)),'error');
  perform pg_temp.t('family','forge no-show resolution refused',FA,'update no_show_record set resolution_status=''waived''','error');
  perform pg_temp.chk('family','no TRUNCATE privilege for signed-in users','false',has_table_privilege('authenticated','public.assignment','TRUNCATE')::text);
  perform pg_temp.chk('family','no DELETE privilege on player','false',has_table_privilege('authenticated','public.player','DELETE')::text);
  perform pg_temp.chk('anon','anon has no table privilege on app_role','false',has_table_privilege('anon','public.app_role','SELECT')::text);
  perform pg_temp.t('family','create family refused',FA,'insert into family(display_name) values (''x'')','error');
  perform pg_temp.t('family','create guardian refused',FA,format('insert into guardian(family_id,full_name) values (%L,''x'')',FAM_A),'error');
  perform pg_temp.t('family','self-approve registration blocked',FA,'update player_season set registration_stage=''season_ready'' where registration_stage=''approved''','affected=0');
  perform pg_temp.t('family','edit family row blocked',FA,'update family set display_name=''hacked''','affected=0');
  perform pg_temp.t('family','guardian tries to set match_status',FA,'update player set match_status=''verified''','ok');
  perform pg_temp.chk('family','match_status unchanged by guardian','confirmed_different_person', (select match_status from player where full_name='Player A1' and family_id=FAM_A));
  perform pg_temp.t('family','apply_auto refused',FA,format('select * from apply_auto_assignments(%L,''[]'')',DEMO),'error~Commissioner');
  perform pg_temp.t('family','cash entry refused',FA,format('select record_cash_entry(%L, 5)',(select id from player_season limit 1)),'error~Commissioner');
  perform pg_temp.t('family','review share refused',FA,format('select review_social_share(%L,true)',gen_random_uuid()),'error~Commissioner');
  perform pg_temp.t('family','season status refused',FA,format('select set_season_status(%L,''closed'')',DEMO),'error~Commissioner');
  perform pg_temp.t('family','create household refused',FA,'select commissioner_create_household(''X Family'',''X Person'',''x@example.test'')','error~Commissioner');
  perform pg_temp.t('family','verify credit refused',FA,format('select verify_replacement_credit(%L)',gen_random_uuid()),'error~Commissioner');
  perform pg_temp.t('family','resolve no-show refused',FA,format('select resolve_no_show(%L,''waived'')',gen_random_uuid()),'error~Commissioner');
  perform pg_temp.t('family','staff check-in refused',FA,'select assignment_check_in(''00000000-0000-0000-0000-00000000e041'')','error~Not authorized');
  perform pg_temp.t('family','closeout refused',FA,format('select * from season_closeout_summary(%L)',DEMO),'error~Commissioner');
  perform pg_temp.t('family','can_close refused',FA,format('select * from can_close_season(%L)',DEMO),'error~Commissioner');

  -- 4 TEAM PARENT / COACH / PLATFORM OWNER
  perform pg_temp.t('team','TP Hawks sees Hawks assignment',TP1,'select * from assignment','rows=1');
  perform pg_temp.t('team','Coach Falcons sees none of Hawks',CO2,'select * from assignment','rows=0');
  perform pg_temp.t('team','Falcons coach cannot check in Hawks job',CO2,'select assignment_check_in(''00000000-0000-0000-0000-00000000e041'')','error~Not authorized');
  perform pg_temp.t('team','TP cannot apply auto',TP1,format('select * from apply_auto_assignments(%L,''[]'')',DEMO),'error~Commissioner');
  perform pg_temp.t('team','TP cannot record cash',TP1,format('select record_cash_entry(%L, 5)',(select id from player_season limit 1)),'error~Commissioner');
  perform pg_temp.t('team','TP cannot read cash ledger',TP1,'select * from fundraising_cash_ledger','rows=0');
  perform pg_temp.t('team','TP cannot closeout',TP1,format('select * from can_close_season(%L)',DEMO),'error~Commissioner');
  perform pg_temp.t('team','TP cannot create household',TP1,'select commissioner_create_household(''X'',''X Person'',''x2@example.test'')','error~Commissioner');
  perform pg_temp.t('platform','platform owner no league rows',PO,'select * from family','rows=0');
  perform pg_temp.t('platform','platform owner no closeout',PO,format('select * from can_close_season(%L)',DEMO),'error~Commissioner');

  -- 5 COMMISSIONER
  perform pg_temp.t('commissioner','sees all families',COMM,'select * from family','rows=10');
  perform pg_temp.t('commissioner','closeout summary ok',COMM,format('select * from season_closeout_summary(%L)',DEMO),'ok');
  perform pg_temp.t('commissioner','can_close ok (not ready)',COMM,format('select * from can_close_season(%L)',DEMO),'has="ready":false');
  perform pg_temp.t('commissioner','direct season status update refused',COMM,format('update season set status=''closed'' where id=%L',DEMO),'error');
  perform pg_temp.t('commissioner','season name edit allowed',COMM,format('update season set name=name where id=%L',DEMO),'affected=1');

  -- 6 HOUSEHOLD CREATE + CLAIM
  v_fam := pg_temp.v(COMM, 'commissioner_create_household(''Demo Household'',''Dana Demo'',''newfam.demo@example.test'',''555-0100'',''Drew Demo'',''drew.demo@example.test'')')::uuid;
  perform pg_temp.chk('household','household created with 2 guardians','2', (select count(*)::text from guardian where family_id=v_fam));
  perform pg_temp.t('household','duplicate email refused',COMM,'select commissioner_create_household(''Dup'',''Dup Person'',''NewFam.Demo@Example.test'')','error~already on a household');
  perform pg_temp.t('household','bad email refused',COMM,'select commissioner_create_household(''Bad'',''Bad Person'',''not-an-email'')','error~valid');
  perform pg_temp.t('household','unverified login not linked',UNC,'select claim_my_household()','has=null');
  perform pg_temp.t('household','verified login linked',NEWF,'select claim_my_household()','has='||v_fam::text);
  perform pg_temp.chk('household','guardian role created once','1', (select count(*)::text from app_role where auth_user_id=NEWF::uuid and role='guardian' and family_id=v_fam));
  perform pg_temp.t('household','claim is idempotent',NEWF,'select claim_my_household()','has='||v_fam::text);
  perform pg_temp.chk('household','still one role row after re-claim','1', (select count(*)::text from app_role where auth_user_id=NEWF::uuid));
  perform pg_temp.t('household','unknown email -> no household',NOR,'select claim_my_household()','has=null');
  insert into guardian(family_id, full_name, email, is_primary) values (FAM_AB,'Alex (demo)','alexben.demo@example.test',true);
  perform pg_temp.t('household','Alex/Ben guardian linked',AB,'select claim_my_household()','has='||FAM_AB::text);
  insert into guardian(family_id, full_name, email) values (FAM_A,'Amb One','ambig.demo@example.test'),(FAM_B,'Amb Two','ambig.demo@example.test');
  perform pg_temp.t('household','email on 2 households fails closed',AMB,'select claim_my_household()','error~more than one household');
  perform pg_temp.chk('household','ambiguous user got no role','0', (select count(*)::text from app_role where auth_user_id=AMB::uuid));

  -- 7 MULTI-CHILD HOUSEHOLD / EXACT MINUTES
  perform pg_temp.t('minutes','Alex+Ben = 360 min required',AB,format('select * from families_owing_hours(%L)',DEMO),'has="required_minutes":360');
  perform pg_temp.t('minutes','Alex+Ben registered_children=2',AB,format('select * from families_owing_hours(%L)',DEMO),'has="registered_children":2');
  perform pg_temp.t('minutes','Alex+Ben sees only own household',AB,format('select * from families_owing_hours(%L)',DEMO),'rows=1');
  perform pg_temp.chk('minutes','Alex+Ben: exactly 2 players in one household','2',(select count(*)::text from player where family_id=FAM_AB));
  perform pg_temp.chk('minutes','merged duplicate family has no players','0',(select count(*)::text from player where family_id='403fcf8b-e222-4d04-bd31-df7d6a6b2113'));

  -- 8 REGISTRATION GUARDS
  perform pg_temp.t('registration','family adds child',FA,format('insert into player(family_id,full_name) values (%L,''QA New Kid'')',FAM_A),'ok');
  select id into v_pl from player where family_id=FAM_A and full_name='QA New Kid';
  perform pg_temp.t('registration','family starts registration (forged fields)',FA,
    format('insert into player_season(player_id,season_id,season_config_id,registration_stage,registration_status,team_id) values (%L,%L,%L,''season_ready'',''pending'',%L)',v_pl,DEMO,v_cfg_leg,'00000000-0000-0000-0000-00000000b011'),'ok');
  select id into v_ps from player_season where player_id=v_pl;
  perform pg_temp.chk('registration','forced to draft','draft',(select registration_stage from player_season where id=v_ps));
  perform pg_temp.chk('registration','forced to current season config',v_cfg_demo::text,(select season_config_id::text from player_season where id=v_ps));
  perform pg_temp.chk('registration','team not self-assigned','null',(select coalesce(team_id::text,'null') from player_season where id=v_ps));
  perform pg_temp.t('registration','family submits (+ tries to swap config)',FA,format('update player_season set registration_stage=''submitted'', season_config_id=%L where id=%L',v_cfg_leg,v_ps),'affected=1');
  perform pg_temp.chk('registration','submitted, config unchanged','submitted|'||v_cfg_demo,(select registration_stage||'|'||season_config_id from player_season where id=v_ps));
  perform pg_temp.t('registration','family cannot self-approve',FA,format('update player_season set registration_stage=''approved'' where id=%L',v_ps),'error');
  perform pg_temp.t('registration','commissioner approves',COMM,format('update player_season set registration_stage=''approved'', reviewed_at=now() where id=%L',v_ps),'affected=1');
  perform pg_temp.t('registration','family cannot edit after approval',FA,format('update player_season set registration_stage=''draft'' where id=%L',v_ps),'affected=0');
  perform pg_temp.chk('registration','readiness fails closed (no team/uniform/ack)','false',(select is_season_ready::text from player_season_readiness(v_ps)));

  -- 9 PHASE A
  v_b := pg_temp.v(FB, format('claim_volunteer_job(%L)',JI_FUT))::uuid;
  perform pg_temp.chk('selection','claim creates scheduled row','scheduled',(select status from assignment where id=v_b));
  perform pg_temp.t('selection','double-tap returns same row',FB,format('select claim_volunteer_job(%L)',JI_FUT),'has='||v_b::text);
  perform pg_temp.chk('selection','still one row for FB on job','1',(select count(*)::text from assignment where job_instance_id=JI_FUT and family_id=FAM_B));
  perform pg_temp.t('selection','family A claims',FA,format('select claim_volunteer_job(%L)',JI_FUT),'ok');
  perform pg_temp.t('selection','job full -> refused',AB,format('select claim_volunteer_job(%L)',JI_FUT),'error~full');
  perform pg_temp.t('selection','started event refused',FA,format('select claim_volunteer_job(%L)',JI_NOW),'error~already started');
  perform pg_temp.t('selection','unregistered household refused',NEWF,format('select claim_volunteer_job(%L)',JI_FUT),'error~registration');
  perform pg_temp.t('selection','Alex/Ben claims snack bar',AB,format('select claim_volunteer_job(%L)',JI_SNACK),'ok');
  perform pg_temp.t('selection','open jobs list (future events only)',FA,format('select * from open_jobs_for_season(%L)',DEMO),'rows=3');
  perform pg_temp.t('selection','family B sees only own assignments',FB,'select * from assignment','rows=1');
  perform pg_temp.t('selection','scheduled minutes exact (AB 90)',AB,format('select * from families_owing_hours(%L)',DEMO),'has="scheduled_minutes":90');

  -- 10 PHASE B
  perform pg_temp.t('phaseB','apply two valid pairs',COMM,format('select * from apply_auto_assignments(%L,%L::jsonb)',DEMO,
    jsonb_build_array(jsonb_build_object('job_instance_id',JI_CHAIN,'family_id',FAM_A),jsonb_build_object('job_instance_id',JI_CHAIN,'family_id',FAM_B))::text),'has="inserted":2');
  perform pg_temp.t('phaseB','re-apply is idempotent',COMM,format('select * from apply_auto_assignments(%L,%L::jsonb)',DEMO,
    jsonb_build_array(jsonb_build_object('job_instance_id',JI_CHAIN,'family_id',FAM_A),jsonb_build_object('job_instance_id',JI_CHAIN,'family_id',FAM_B))::text),'has="skipped":2');
  perform pg_temp.chk('phaseB','claimed_via auto_assigned','auto_assigned',(select claimed_via from assignment where job_instance_id=JI_CHAIN and family_id=FAM_A));
  perform pg_temp.t('phaseB','stale proposal (job full) fails',COMM,format('select * from apply_auto_assignments(%L,%L::jsonb)',DEMO,
    jsonb_build_array(jsonb_build_object('job_instance_id',JI_SNACK,'family_id',FAM_B))::text),'error~full');
  perform pg_temp.t('phaseB','unregistered family pair fails',COMM,format('select * from apply_auto_assignments(%L,%L::jsonb)',DEMO,
    jsonb_build_array(jsonb_build_object('job_instance_id',JI_NOW,'family_id',v_fam))::text),'error~registration');
  perform pg_temp.t('phaseB','batch is atomic (valid + invalid)',COMM,format('select * from apply_auto_assignments(%L,%L::jsonb)',DEMO,
    jsonb_build_array(jsonb_build_object('job_instance_id',JI_NOW,'family_id',FAM_A),jsonb_build_object('job_instance_id',JI_NOW,'family_id',v_fam))::text),'error');
  perform pg_temp.chk('phaseB','nothing partially applied','0',(select count(*)::text from assignment where job_instance_id=JI_NOW));
  perform pg_temp.t('phaseB','malformed payload refused',COMM,format('select * from apply_auto_assignments(%L,''{"x":1}''::jsonb)',DEMO),'error~list');
  perform pg_temp.t('phaseB','apply for Game Day job (3 households)',COMM,format('select * from apply_auto_assignments(%L,%L::jsonb)',DEMO,
    jsonb_build_array(jsonb_build_object('job_instance_id',JI_NOW,'family_id',FAM_A),jsonb_build_object('job_instance_id',JI_NOW,'family_id',FAM_B),jsonb_build_object('job_instance_id',JI_NOW,'family_id',FAM_AB))::text),'has="inserted":3');
  perform pg_temp.t('team','Falcons coach sees only Falcons job',CO2,'select * from assignment','rows=2');
  perform pg_temp.t('team','Hawks TP cannot see Falcons job',TP1,format('select * from assignment where job_instance_id=%L',JI_CHAIN),'rows=0');
  perform pg_temp.t('team','Falcons coach cannot see Hawks Game Day job',CO2,format('select * from assignment where job_instance_id=%L',JI_NOW),'rows=0');

  -- 11 GAME DAY
  select id into v_a from assignment where job_instance_id=JI_NOW and family_id=FAM_A;
  select id into v_b from assignment where job_instance_id=JI_NOW and family_id=FAM_B;
  perform pg_temp.t('gameday','Falcons coach cannot check in',CO2,format('select assignment_check_in(%L)',v_a),'error~Not authorized');
  perform pg_temp.t('gameday','family cannot check itself in',FA,format('select assignment_check_in(%L)',v_a),'error~Not authorized');
  perform pg_temp.t('gameday','cannot complete before check-in',TP1,format('select assignment_complete(%L,60)',v_b),'error~Cannot complete');
  perform pg_temp.t('gameday','TP checks in',TP1,format('select assignment_check_in(%L)',v_a),'ok');
  perform pg_temp.t('gameday','check-in idempotent',TP1,format('select assignment_check_in(%L)',v_a),'ok');
  perform pg_temp.t('gameday','0 minutes refused',TP1,format('select assignment_complete(%L,0)',v_a),'error~between');
  perform pg_temp.t('gameday','800 minutes refused',TP1,format('select assignment_complete(%L,800)',v_a),'error~between');
  perform pg_temp.t('gameday','complete with exact 95 minutes',TP1,format('select assignment_complete(%L,95)',v_a),'ok');
  perform pg_temp.chk('gameday','minutes stored exactly','95',(select actual_minutes_worked::text from assignment where id=v_a));
  perform pg_temp.t('gameday','family cannot verify own time',FA,format('select assignment_verify(%L)',v_a),'error~designated');
  perform pg_temp.t('gameday','wrong-team coach cannot verify',CO2,format('select assignment_verify(%L)',v_a),'error~designated');
  perform pg_temp.t('gameday','designated TP verifies',TP1,format('select assignment_verify(%L)',v_a),'ok');
  perform pg_temp.t('gameday','verify idempotent',TP1,format('select assignment_verify(%L)',v_a),'ok');
  perform pg_temp.chk('gameday','verified_by_role','team_parent',(select verified_by_role from assignment where id=v_a));
  perform pg_temp.chk('minutes','household verified minutes = 95 (not 120)','95',(select verified_minutes::text from families_owing_hours(DEMO) where family_id=FAM_A));
  perform pg_temp.chk('minutes','remaining = 360-95 (2 kids in demo season for A)','265',(select remaining_minutes::text from families_owing_hours(DEMO) where family_id=FAM_A));
  perform pg_temp.chk('gameday','audit trail rows for assignment','4',(select count(*)::text from assignment_audit_log where assignment_id=v_a));

  -- 12 NO-SHOW
  perform pg_temp.t('noshow','TP cannot record no-show',TP1,format('select assignment_report_no_show(%L)',v_b),'error~Commissioner');
  perform pg_temp.t('noshow','future event refused',COMM,format('select assignment_report_no_show(%L)',(select id from assignment where job_instance_id=JI_FUT and family_id=FAM_B)),'error~not started');
  v_ns := pg_temp.v(COMM, format('assignment_report_no_show(%L)',v_b))::uuid;
  perform pg_temp.chk('noshow','fee = config $50, pay-by = +5 days','50|'||(current_date+5)::text,(select fee_amount::text||'|'||pay_by_date::text from no_show_record where id=v_ns));
  perform pg_temp.t('noshow','recording twice returns same',COMM,format('select assignment_report_no_show(%L)',v_b),'has='||v_ns::text);
  perform pg_temp.chk('noshow','one record only','1',(select count(*)::text from no_show_record where assignment_id=v_b));
  perform pg_temp.chk('noshow','assignment is no_show','no_show',(select status from assignment where id=v_b));
  perform pg_temp.t('noshow','unresolved no-show blocks closeout',COMM,format('select * from can_close_season(%L)',DEMO),'has=no-show fee(s) unresolved');
  perform pg_temp.t('noshow','Game Day coverage shows unresolved job',TP1,format('select * from job_instance_coverage(%L) where role_name=''Gate''',GM_NOW),'has="unresolved_count":1');
  perform pg_temp.t('noshow','TP cannot resolve',TP1,format('select resolve_no_show(%L,''waived'')',v_ns),'error~Commissioner');
  perform pg_temp.t('noshow','invalid resolution refused',COMM,format('select resolve_no_show(%L,''foo'')',v_ns),'error~Resolution');
  perform pg_temp.t('noshow','commissioner waives',COMM,format('select resolve_no_show(%L,''waived'')',v_ns),'ok');
  perform pg_temp.t('noshow','resolve idempotent',COMM,format('select resolve_no_show(%L,''waived'')',v_ns),'ok');
  perform pg_temp.t('noshow','cannot flip resolved',COMM,format('select resolve_no_show(%L,''paid'')',v_ns),'error~already resolved');
  perform pg_temp.chk('noshow','no-show fee never touches cash ledger',v_cash::text,(select count(*)::text from fundraising_cash_ledger));

  -- 13 $25 REPLACEMENT
  select id into v_x from assignment where job_instance_id=JI_FUT and family_id=FAM_A;
  perform pg_temp.t('replacement','other household cannot request',FB,format('select request_replacement(%L)',v_x),'error~not your household');
  v_e := pg_temp.v(FA, format('request_replacement(%L)',v_x))::uuid;
  perform pg_temp.chk('replacement','fee snapshot $25 + status','25|replacement_requested',(select fee_amount::text||'|'||(select status from assignment where id=v_x) from replacement_pool_entry where id=v_e));
  perform pg_temp.t('replacement','request idempotent',FA,format('select request_replacement(%L)',v_x),'has='||v_e::text);
  perform pg_temp.t('replacement','cannot claim own release',FA,format('select claim_replacement_shift(%L)',v_e),'error~cannot claim');
  perform pg_temp.t('replacement','open shifts visible to others',AB,format('select * from open_replacement_shifts(%L)',DEMO),'rows=1');
  perform pg_temp.t('replacement','releaser does not see own shift',FA,format('select * from open_replacement_shifts(%L)',DEMO),'rows=0');
  perform pg_temp.t('replacement','unregistered household cannot claim',NEWF,format('select claim_replacement_shift(%L)',v_e),'error~registration');
  perform pg_temp.t('replacement','Alex/Ben household claims',AB,format('select claim_replacement_shift(%L)',v_e),'ok');
  perform pg_temp.t('replacement','second claimer loses race',FB,format('select claim_replacement_shift(%L)',v_e),'error~already claimed');
  perform pg_temp.chk('replacement','NO credit on claim','0',(select count(*)::text from fundraising_credit_ledger where source_reference_id=v_e));
  perform pg_temp.t('replacement','cannot complete before event',TP1,format('select complete_replacement_shift(%L)',v_e),'error~not started');
  update game_event set starts_at = now() - interval '1 hour' where id = GM_FUT;
  perform pg_temp.t('replacement','family cannot mark completed',FB,format('select complete_replacement_shift(%L)',v_e),'error~Not authorized');
  perform pg_temp.t('replacement','TP marks shift completed',TP1,format('select complete_replacement_shift(%L)',v_e),'ok');
  perform pg_temp.chk('replacement','NO credit on completion alone','0',(select count(*)::text from fundraising_credit_ledger where source_reference_id=v_e));
  perform pg_temp.t('replacement','TP cannot issue credit',TP1,format('select verify_replacement_credit(%L)',v_e),'error~Commissioner');
  perform pg_temp.t('replacement','commissioner verifies -> credit',COMM,format('select verify_replacement_credit(%L)',v_e),'ok');
  perform pg_temp.t('replacement','verify idempotent (no double credit)',COMM,format('select verify_replacement_credit(%L)',v_e),'ok');
  perform pg_temp.chk('replacement','exactly one $25 HOUSEHOLD credit to claimer','1|25|'||FAM_AB||'|null',
    (select count(*)::text||'|'||max(amount)::text||'|'||max(family_id::text)||'|'||coalesce(max(player_season_id::text),'null') from fundraising_credit_ledger where source_reference_id=v_e));
  perform pg_temp.chk('replacement','original assignment closed','cancelled',(select status from assignment where id=v_x));
  perform pg_temp.chk('replacement','claimer earned NO volunteer minutes','0',(select verified_minutes::text from families_owing_hours(DEMO) where family_id=FAM_AB));
  perform pg_temp.chk('replacement','cash ledger untouched',v_cash::text,(select count(*)::text from fundraising_cash_ledger));
  perform pg_temp.t('replacement','household sees $25 credit',AB,format('select * from family_fundraising_summary(%L,%L)',FAM_AB,DEMO),'has="credit_total":25');
  begin
    insert into fundraising_credit_ledger(family_id,source,source_reference_id,amount) values (FAM_AB,'replacement_pool',v_e,25);
    perform pg_temp.chk('replacement','DB backstop blocks duplicate credit','blocked','NOT BLOCKED');
  exception when unique_violation then perform pg_temp.chk('replacement','DB backstop blocks duplicate credit','blocked','blocked'); end;

  -- 14 $1 SOCIAL SHARE
  select ps.id into v_ps from player_season ps join player p on p.id=ps.player_id where p.full_name='Player A1' and ps.season_id=DEMO and p.family_id=FAM_A;
  perform pg_temp.t('share','family files share (forging approved/$999)',FA,format('insert into social_share_submission(player_season_id,proof_url,status,credit_amount,reviewed_by) values (%L,''https://example.test/p1'',''approved'',999,%L)',v_ps,FA),'ok');
  select id into v_sub from social_share_submission where proof_url='https://example.test/p1';
  perform pg_temp.chk('share','forced pending, config amount, no reviewer','pending|1|null',(select status||'|'||credit_amount::text||'|'||coalesce(reviewed_by::text,'null') from social_share_submission where id=v_sub));
  perform pg_temp.t('share','non-link proof refused',FA,format('insert into social_share_submission(player_season_id,proof_url) values (%L,''just trust me'')',v_ps),'error~link');
  perform pg_temp.t('share','other household cannot file for my child',FB,format('insert into social_share_submission(player_season_id,proof_url) values (%L,''https://example.test/zz'')',v_ps),'error');
  perform pg_temp.t('share','family cannot approve own',FA,format('select review_social_share(%L,true)',v_sub),'error~Commissioner');
  perform pg_temp.t('share','family cannot direct-update',FA,format('update social_share_submission set status=''approved'' where id=%L',v_sub),'error');
  perform pg_temp.chk('share','no credit while pending','0',(select count(*)::text from fundraising_credit_ledger where source='social_share'));
  perform pg_temp.t('share','commissioner approves',COMM,format('select review_social_share(%L,true)',v_sub),'ok');
  perform pg_temp.t('share','approve idempotent',COMM,format('select review_social_share(%L,true)',v_sub),'ok');
  perform pg_temp.chk('share','exactly one $1 credit on the child','1|1|'||v_ps,(select count(*)::text||'|'||max(amount)::text||'|'||max(player_season_id::text) from fundraising_credit_ledger where source_reference_id=v_sub));
  insert into social_share_submission(player_season_id,proof_url) values (v_ps,'https://example.test/p1') returning id into v_sub2;
  perform pg_temp.t('share','same proof cannot earn twice',COMM,format('select review_social_share(%L,true)',v_sub2),'error~already approved');
  perform pg_temp.t('share','reject path',COMM,format('select review_social_share(%L,false)',v_sub2),'ok');
  perform pg_temp.t('share','cannot approve after reject',COMM,format('select review_social_share(%L,true)',v_sub2),'error~already rejected');
  insert into social_share_submission(player_season_id,proof_url) values (v_ps,'https://example.test/p3') returning id into v_k;
  update season_config set share_credit_board_approved=false where id=v_cfg_demo;
  perform pg_temp.t('share','board gate fails closed',COMM,format('select review_social_share(%L,true)',v_k),'error~board');
  update season_config set share_credit_board_approved=true where id=v_cfg_demo;

  -- 15 CASH
  v_x := pg_temp.v(COMM, format('record_cash_entry(%L,20,''chocolate sale'',null,''k1'')',v_ps))::uuid;
  perform pg_temp.t('cash','same idempotency key returns same row',COMM,format('select record_cash_entry(%L,20,''chocolate sale'',null,''k1'')',v_ps),'has='||v_x::text);
  perform pg_temp.chk('cash','one row for key','1',(select count(*)::text from fundraising_cash_ledger where idempotency_key='k1'));
  perform pg_temp.t('cash','zero refused',COMM,format('select record_cash_entry(%L,0)',v_ps),'error~non-zero');
  perform pg_temp.t('cash','sub-cent refused',COMM,format('select record_cash_entry(%L,0.001)',v_ps),'error~decimal');
  perform pg_temp.t('cash','over single-entry limit refused',COMM,format('select record_cash_entry(%L,6000)',v_ps),'error~limit');
  perform pg_temp.t('cash','reversal needs note',COMM,format('select record_cash_entry(%L,-5)',v_ps),'error~note');
  perform pg_temp.t('cash','reversal with note ok',COMM,format('select record_cash_entry(%L,-5,''entered twice by mistake'')',v_ps),'ok');
  perform pg_temp.t('cash','reversal beyond cash refused',COMM,format('select record_cash_entry(%L,-100,''too big reversal'')',v_ps),'error~larger');
  perform pg_temp.t('cash','planning season refused',COMM,format('select record_cash_entry(%L,5)',(select ps.id from player_season ps where ps.season_id=LEG limit 1)),'error~not open');
  perform pg_temp.t('cash','team parent refused',TP1,format('select record_cash_entry(%L,5)',v_ps),'error~Commissioner');
  perform pg_temp.chk('cash','append-only: 2 rows, net $15','2|15',(select count(*)::text||'|'||sum(amount)::text from fundraising_cash_ledger where player_season_id=v_ps));
  perform pg_temp.t('cash','family sees cash $15',FA,format('select * from family_fundraising_summary(%L,%L)',FAM_A,DEMO),'has="cash_total":15');
  perform pg_temp.t('cash','credit stays separate (25 seeded + $1 share = 26)',FA,format('select * from family_fundraising_summary(%L,%L)',FAM_A,DEMO),'has="credit_total":26');
  perform pg_temp.t('cash','family B cannot see A cash',FB,'select * from fundraising_cash_ledger','rows=0');
  perform pg_temp.t('cash','family sees own child cash rows',FA,'select * from fundraising_cash_ledger','rows=2');

  -- 16 SEASON STATUS
  perform pg_temp.t('season','second open season refused',COMM,format('select set_season_status(%L,''registration_open'')',LEG),'error~Another season');
  perform pg_temp.t('season','close with unresolved items refused',COMM,format('select set_season_status(%L,''closed'')',DEMO),'error~cannot be closed');
  perform pg_temp.t('season','invalid target refused',COMM,format('select set_season_status(%L,''planning'')',DEMO),'error~Status must be');
  insert into season(org_name,name,status) values ('Fremont','TMP empty','active') returning id into v_tmp;
  perform pg_temp.t('season','empty season closes (vacuous ready - noted)',COMM,format('select set_season_status(%L,''closed'')',v_tmp),'ok');

  -- 17 MIGRATION 025 REGRESSION
  perform pg_temp.t('mig025','all-draft legacy season NOT ready',COMM,format('select * from can_close_season(%L)',LEG),'has="ready":false');
  insert into season(org_name,name,status) values ('Fremont','TMP 025','planning') returning id into v_t2;
  insert into season_config(season_id, minutes_per_child) values (v_t2,180);
  select id into v_k from season_config where season_id=v_t2;
  select ps.player_id into v_pl from player_season ps where ps.id=v_ps;
  insert into player_season(player_id,season_id,season_config_id,registration_stage,registration_status) values (v_pl,v_t2,v_k,'season_ready','pending') returning id into v_x;
  perform pg_temp.t('mig025','season_ready only -> ready',COMM,format('select * from can_close_season(%L)',v_t2),'has="ready":true');
  update player_season set registration_stage='draft' where id=v_x;
  perform pg_temp.t('mig025','draft -> NOT ready',COMM,format('select * from can_close_season(%L)',v_t2),'has="ready":false');
  update player_season set registration_stage='approved' where id=v_x;
  perform pg_temp.t('mig025','approved -> NOT ready',COMM,format('select * from can_close_season(%L)',v_t2),'has="ready":false');
  update player_season set registration_stage='waitlisted' where id=v_x;
  perform pg_temp.t('mig025','waitlisted -> NOT ready',COMM,format('select * from can_close_season(%L)',v_t2),'has="ready":false');
  update player_season set registration_stage='withdrawn' where id=v_x;
  perform pg_temp.t('mig025','withdrawn -> ready',COMM,format('select * from can_close_season(%L)',v_t2),'has="ready":true');
  update player_season set registration_stage='refunded' where id=v_x;
  perform pg_temp.t('mig025','refunded -> ready',COMM,format('select * from can_close_season(%L)',v_t2),'has="ready":true');

  -- 18 REPORTS
  perform pg_temp.t('reports','closeout summary returns fundraising totals',COMM,format('select * from season_closeout_summary(%L)',DEMO),'has="fundraising_raised"');
  perform pg_temp.t('reports','closeout summary (show payload)',COMM,format('select * from season_closeout_summary(%L)',DEMO),'has=volunteer');

  select string_agg(format('%s | %s | expect %s | got %s', area, name, expect, actual), E'\n' order by n) into v_txt from results where not pass;
  raise exception E'QA_RESULTS total=% pass=% fail=%\n--- FAILS ---\n%\n--- REPORT PAYLOAD ---\n%', (select count(*) from results), (select count(*) from results where pass), (select count(*) from results where not pass), coalesce(v_txt,'(none)'),
    (select actual from results where name='closeout summary (show payload)');
end $$;
