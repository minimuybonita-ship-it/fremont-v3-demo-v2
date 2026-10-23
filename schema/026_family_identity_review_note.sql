alter table family add column if not exists identity_review_note text;
alter table family add column if not exists identity_reviewed_at timestamptz;
comment on column family.identity_review_note is
  'Audit trail for a human identity/household decision (who/what/when). Never auto-populated by the app or by scans.';
