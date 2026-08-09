-- Fitness Tracker server schema. Mirrors the on-device SQLite schema
-- (TECH_DESIGN.md §2): same tables, same camelCase columns, same client-side
-- UUID text ids. Every row is scoped to its owner via "userId" + row-level
-- security; the app never sends userId — the default fills it from the JWT.

create table public.exercise (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  kind text not null,
  unique ("userId", name)
);

create table public.template (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  position integer not null,
  "archivedAt" timestamptz
);

create table public."templateItem" (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  "templateId" text not null references public.template (id) on delete cascade,
  "exerciseId" text not null references public.exercise (id),
  position integer not null,
  "supersetGroup" integer,
  "restSeconds" integer,
  "targetSetCount" integer
);

create table public.workout (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  "templateId" text references public.template (id) on delete set null,
  name text not null,
  "startedAt" timestamptz not null,
  "finishedAt" timestamptz,
  notes text,
  unique ("userId", "startedAt", name)
);

create table public."workoutItem" (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  "workoutId" text not null references public.workout (id) on delete cascade,
  "exerciseId" text not null references public.exercise (id),
  position integer not null,
  "supersetGroup" integer,
  "restSeconds" integer
);

create table public."workoutSet" (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  "workoutItemId" text not null references public."workoutItem" (id) on delete cascade,
  position integer not null,
  "isWarmup" boolean not null default false,
  weight double precision,
  reps integer,
  seconds double precision,
  distance double precision,
  notes text,
  "completedAt" timestamptz
);

create table public."bodyWeight" (
  id text primary key,
  "userId" uuid not null default auth.uid() references auth.users (id) on delete cascade,
  "measuredAt" timestamptz not null,
  weight double precision not null
);

create table public.settings (
  "userId" uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  "weeklyGoal" integer not null default 3,
  unit text not null default 'lbs'
);

create index on public."templateItem" ("templateId");
create index on public."workoutItem" ("workoutId");
create index on public."workoutItem" ("exerciseId");
create index on public."workoutSet" ("workoutItemId");
create index on public.workout ("userId", "startedAt");

-- Row-level security: every user sees exactly their own rows, nothing else.
do $$
declare t text;
begin
  foreach t in array array['exercise','template','templateItem','workout','workoutItem','workoutSet','bodyWeight','settings']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "own rows" on public.%I for all to authenticated using ("userId" = auth.uid()) with check ("userId" = auth.uid())', t);
  end loop;
end $$;
