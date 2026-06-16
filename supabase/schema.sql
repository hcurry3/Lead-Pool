-- ============================================================================
-- For The People — Lead Engine: Postgres schema + Row-Level Security (RLS)
-- Run this once in Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run (idempotent).
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------- profiles (one row per agent, linked to Supabase Auth user) -------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null default '',
  email      text,
  team       text default 'Unassigned',
  upline     text default 'Owner',
  role       text not null default 'agent'    check (role   in ('owner','agent')),
  status     text not null default 'pending'  check (status in ('pending','active','rejected')),
  created_at timestamptz not null default now()
);

-- ---------- leads -----------------------------------------------------------
create table if not exists public.leads (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null default '',
  phone              text default '',
  email              text default '',
  dob                text default '',
  gender             text default '',
  state              text default '',
  age                int  default 0,
  status             text not null default 'available',
  dnc                boolean default false,
  chargeback_client  boolean default false,
  imported_by        text default '',
  imported_at        date,
  import_batch       text default '',
  current_owner      uuid references public.profiles(id),
  current_owner_name text default '',
  times_worked       int default 0,
  last_called_by     text default '',
  last_called_date   date,
  last_disposition   text default '',
  followup_date      date,
  followup_time      text default '',
  followup_kind      text default '',
  followup_set_by    text default '',
  touched_by         jsonb default '[]'::jsonb,
  dismissed_by       jsonb default '[]'::jsonb,
  notes              jsonb default '[]'::jsonb,
  created_at         timestamptz not null default now()
);

-- ---------- deals -----------------------------------------------------------
create table if not exists public.deals (
  id               uuid primary key default gen_random_uuid(),
  lead_id          uuid,
  lead_name        text default '',
  closed_by        text default '',
  closer_team      text default '',
  closer_upline    text default '',
  carrier          text default '',
  annual_ap        numeric default 0,
  monthly_premium  numeric default 0,
  coverage_amount  numeric default 0,
  draft_date       date,
  effective_date   date,
  close_date       date,
  policy_number    text default '',
  status           text not null default 'active',
  created_at       timestamptz not null default now()
);

-- ---------- role helpers (SECURITY DEFINER avoids RLS recursion) -------------
create or replace function public.is_owner() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'owner' and p.status = 'active');
$$;

create or replace function public.is_active() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.status = 'active');
$$;

-- ---------- auto-create a PENDING profile for every new auth user ------------
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, status, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'name',''), new.email, 'pending', 'agent')
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- block privilege escalation: only the owner may change role/status/
--            team/upline. Agents can edit their own name/email only. ----------
create or replace function public.protect_profile_fields() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  -- block privileged-field changes by signed-in non-owners; trusted admin
  -- updates (SQL editor / service role, where auth.uid() is null) are allowed.
  if auth.uid() is not null and not public.is_owner() then
    new.role   := old.role;
    new.status := old.status;
    new.team   := old.team;
    new.upline := old.upline;
  end if;
  return new;
end; $$;

drop trigger if exists protect_profile on public.profiles;
create trigger protect_profile
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- ============================ Row-Level Security =============================
alter table public.profiles enable row level security;
alter table public.leads    enable row level security;
alter table public.deals    enable row level security;

-- profiles: everyone signed in can read (for team/leaderboard display);
-- you can update your own row (privileged fields still locked by the trigger),
-- or the owner can update anyone; only the owner deletes.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_owner())
  with check (id = auth.uid() or public.is_owner());
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles for delete to authenticated using (public.is_owner());

-- leads: any ACTIVE (approved) agent can read/insert/update the shared pool;
-- only the owner can delete.
drop policy if exists leads_select on public.leads;
create policy leads_select on public.leads for select to authenticated using (public.is_active());
drop policy if exists leads_insert on public.leads;
create policy leads_insert on public.leads for insert to authenticated with check (public.is_active());
drop policy if exists leads_update on public.leads;
create policy leads_update on public.leads for update to authenticated using (public.is_active()) with check (public.is_active());
drop policy if exists leads_delete on public.leads;
create policy leads_delete on public.leads for delete to authenticated using (public.is_owner());

-- deals: active agents can read and create (a sale); only the owner can
-- update (chargebacks) or delete.
drop policy if exists deals_select on public.deals;
create policy deals_select on public.deals for select to authenticated using (public.is_active());
drop policy if exists deals_insert on public.deals;
create policy deals_insert on public.deals for insert to authenticated with check (public.is_active());
drop policy if exists deals_update on public.deals;
create policy deals_update on public.deals for update to authenticated using (public.is_owner()) with check (public.is_owner());
drop policy if exists deals_delete on public.deals;
create policy deals_delete on public.deals for delete to authenticated using (public.is_owner());

-- ============================================================================
-- AFTER you sign up your own account in the app, promote it to owner+active:
--   update public.profiles set role='owner', status='active'
--   where email = 'YOUR_EMAIL_HERE';
-- ============================================================================
