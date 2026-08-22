-- Per-set rest override (mirrors local migration v3-set-rest).
-- Run this in the Supabase SQL editor before re-enabling cloud backup.
alter table "workoutSet" add column if not exists "restSeconds" integer;
