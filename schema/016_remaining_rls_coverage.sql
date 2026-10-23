alter table job_role_config enable row level security;
alter table job_template enable row level security;
alter table job_template_item enable row level security;
alter table job_instance enable row level security;
alter table game_event enable row level security;
alter table training_resource enable row level security;
alter table org_event enable row level security;
alter table event_signup_item enable row level security;
alter table fundraising_campaign enable row level security;
alter table no_show_record enable row level security;
alter table social_share_submission enable row level security;

create policy job_role_config_read_all on job_role_config for select using (true);
create policy job_role_config_commissioner_write on job_role_config for all using (auth_is_commissioner());

create policy job_template_read_all on job_template for select using (true);
create policy job_template_commissioner_write on job_template for all using (auth_is_commissioner());

create policy job_template_item_read_all on job_template_item for select using (true);
create policy job_template_item_commissioner_write on job_template_item for all using (auth_is_commissioner());

create policy game_event_read_all on game_event for select using (true);
create policy game_event_staff_write on game_event for all using (
  auth_is_commissioner() or team_id in (select auth_team_ids())
);

create policy job_instance_read_all on job_instance for select using (true);
create policy job_instance_commissioner_write on job_instance for all using (auth_is_commissioner());

create policy training_resource_read_all on training_resource for select using (true);
create policy training_resource_commissioner_write on training_resource for all using (auth_is_commissioner());

create policy org_event_read_all on org_event for select using (true);
create policy org_event_commissioner_write on org_event for all using (auth_is_commissioner());

create policy event_signup_item_read_all on event_signup_item for select using (true);
create policy event_signup_item_write on event_signup_item for all using (
  auth_is_commissioner() or claimed_by_family_id in (select auth_family_ids()) or claimed_by_family_id is null
);

create policy fundraising_campaign_read_all on fundraising_campaign for select using (true);
create policy fundraising_campaign_commissioner_write on fundraising_campaign for all using (auth_is_commissioner());

create policy no_show_record_scoped_read on no_show_record for select using (
  family_id in (select auth_family_ids())
  or assignment_id in (
    select a.id from assignment a
    join job_instance ji on ji.id = a.job_instance_id
    join game_event ge on ge.id = ji.game_event_id
    where ge.team_id in (select auth_team_ids())
  )
  or auth_is_commissioner()
);
create policy no_show_record_insert on no_show_record for insert with check (
  auth_is_commissioner()
  or assignment_id in (
    select a.id from assignment a
    join job_instance ji on ji.id = a.job_instance_id
    join game_event ge on ge.id = ji.game_event_id
    where ge.team_id in (select auth_team_ids())
  )
);
create policy no_show_record_commissioner_update on no_show_record for update using (auth_is_commissioner());

create policy social_share_submission_scoped_read on social_share_submission for select using (
  player_season_id in (
    select ps.id from player_season ps join player p on p.id = ps.player_id
    where p.family_id in (select auth_family_ids())
  )
  or auth_is_commissioner()
);
create policy social_share_submission_family_insert on social_share_submission for insert with check (
  player_season_id in (
    select ps.id from player_season ps join player p on p.id = ps.player_id
    where p.family_id in (select auth_family_ids())
  )
);
create policy social_share_submission_commissioner_update on social_share_submission for update using (auth_is_commissioner());
