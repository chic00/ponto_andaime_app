-- =========================================================
-- Ponto do Andaime — schema Supabase (rodar no SQL Editor)
-- =========================================================

create extension if not exists pgcrypto;

create table public.rentals (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users(id),
  customer_name text not null,
  document text,
  phone text,
  whatsapp text,
  email text,
  customer_notes text,
  rental_date date,
  expected_return_date date,
  equipment_type text,
  quantity text,
  description text,
  rental_notes text,
  address text,
  number text,
  complement text,
  neighborhood text,
  city text,
  state text,
  zip_code text,
  location_url text,
  manual_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.photos (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null references public.rentals(id) on delete cascade,
  storage_path text not null,
  description text,
  created_at timestamptz not null default now()
);

create table public.settings (
  id int primary key default 1,
  company_name text default 'Ponto do Andaime',
  phone text,
  whatsapp text,
  email text,
  address text,
  city text,
  state text,
  constraint single_row check (id = 1)
);
insert into public.settings (id) values (1) on conflict do nothing;

-- Row Level Security: só o dono autenticado enxerga/edita os próprios dados.
alter table public.rentals enable row level security;
alter table public.photos enable row level security;
alter table public.settings enable row level security;

create policy "owner_all_rentals" on public.rentals for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

create policy "owner_all_photos" on public.photos for all
  using (exists (select 1 from public.rentals r where r.id = rental_id and r.owner = auth.uid()))
  with check (exists (select 1 from public.rentals r where r.id = rental_id and r.owner = auth.uid()));

create policy "auth_all_settings" on public.settings for all
  using (auth.uid() is not null) with check (auth.uid() is not null);

-- =========================================================
-- Depois de rodar isto, crie o bucket de fotos manualmente em
-- Storage > New bucket > nome exato: andaime-fotos > Public: OFF
-- Em seguida rode o bloco abaixo para liberar acesso ao dono autenticado.
-- =========================================================

create policy "owner_photos_storage_select" on storage.objects for select
  using (bucket_id = 'andaime-fotos' and auth.uid() is not null);
create policy "owner_photos_storage_insert" on storage.objects for insert
  with check (bucket_id = 'andaime-fotos' and auth.uid() is not null);
create policy "owner_photos_storage_delete" on storage.objects for delete
  using (bucket_id = 'andaime-fotos' and auth.uid() is not null);
