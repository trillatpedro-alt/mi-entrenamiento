-- Trillat Coaching — esquema Supabase (v2: bloque unico de datos por cliente)
-- Si ya corriste una version anterior de este archivo, este script la reemplaza sin problema
-- (las tablas routines/sessions/checkins de la v1 estaban vacias, no se pierde nada al borrarlas).
-- Pega TODO este archivo en Supabase → SQL Editor → New query → Run.

drop table if exists coach_notes cascade;
drop table if exists checkins cascade;
drop table if exists sessions cascade;
drop table if exists routines cascade;
drop table if exists client_data cascade;
drop table if exists profiles cascade;
drop function if exists is_owner_or_coach(uuid);

-- ============ TABLAS ============

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('coach','client')),
  display_name text,
  coach_id uuid references profiles(id),      -- solo si role='client'
  invite_code text unique,                    -- solo si role='coach'
  created_at timestamptz default now()
);

-- un solo bloque de datos por cliente: mismo shape que hoy usa localStorage
-- (routines, sessions, checkins, etc. todo dentro de la columna "data")
create table client_data (
  client_id uuid primary key references profiles(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz default now()
);

create table coach_notes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references profiles(id) on delete cascade not null,
  coach_id uuid references profiles(id) on delete cascade not null,
  message text not null,
  created_at timestamptz default now(),
  read_at timestamptz
);

-- ============ ROW LEVEL SECURITY ============

alter table profiles enable row level security;
alter table client_data enable row level security;
alter table coach_notes enable row level security;

create policy "profiles: ver la propia" on profiles
  for select using (id = auth.uid());

create policy "profiles: coach ve sus clientes" on profiles
  for select using (coach_id = auth.uid());

create policy "profiles: buscar coach por invite_code" on profiles
  for select using (role = 'coach');

create policy "profiles: crear la propia" on profiles
  for insert with check (id = auth.uid());

create policy "profiles: editar la propia" on profiles
  for update using (id = auth.uid());

create or replace function is_owner_or_coach(row_client_id uuid)
returns boolean language sql stable as $$
  select row_client_id = auth.uid()
    or exists (select 1 from profiles where id = row_client_id and coach_id = auth.uid());
$$;

create policy "client_data: dueno o coach" on client_data
  for all using (is_owner_or_coach(client_id)) with check (is_owner_or_coach(client_id));

create policy "notes: cliente lee las suyas, coach lee las que escribio" on coach_notes
  for select using (client_id = auth.uid() or coach_id = auth.uid());

create policy "notes: coach crea para sus clientes" on coach_notes
  for insert with check (coach_id = auth.uid() and is_owner_or_coach(client_id));

create policy "notes: cliente marca como leida" on coach_notes
  for update using (client_id = auth.uid());
