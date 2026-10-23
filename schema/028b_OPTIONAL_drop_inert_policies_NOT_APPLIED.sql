-- 028b (OPTIONAL, NOT APPLIED). Tidy-up only; security does not depend on it because 027 revoked the
-- table privileges these policies would have used. Apply only with Minerva's explicit approval.
drop policy if exists assignment_family_claim                     on assignment;
drop policy if exists assignment_staff_manage                     on assignment;
drop policy if exists assignment_audit_log_insert                 on assignment_audit_log;
drop policy if exists no_show_record_insert                       on no_show_record;
drop policy if exists no_show_record_commissioner_update          on no_show_record;
drop policy if exists social_share_submission_commissioner_update on social_share_submission;
