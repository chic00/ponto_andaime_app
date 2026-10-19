-- =========================================================================
-- Ponto do Andaime — SCHEMA CONSOLIDADO (documento de referência)
-- =========================================================================
-- ATENÇÃO: NÃO rode este arquivo contra o banco que já está em produção —
-- as tabelas já existem lá, criadas por 6 migrações separadas ao longo do
-- tempo (schema-supabase.sql, migracao-clientes.sql, migracao-itens.sql,
-- migracao-encerramento.sql, migracao-lixeira.sql,
-- migracao-seguranca-fotos.sql). Rodar isto de novo daria erro de "tabela
-- já existe" — e não tem problema nenhum nisso, é só evitar confusão.
--
-- PARA QUE SERVE ESTE ARQUIVO:
-- É o retrato de "como o banco está hoje, tudo junto", útil para:
--   1) Recriar o banco do zero (ambiente de teste, ou se precisar migrar
--      de projeto Supabase um dia).
--   2) Entender a estrutura completa sem precisar ler 6 arquivos soltos.
--   3) Servir de base para o próximo módulo (financeiro, estoque, etc.)
--      seguir o mesmo padrão de owner + RLS já estabelecido.
--
-- Gerado em: 2026-08-29, refletindo o estado após todas as migrações
-- aplicadas até esta data.
-- =========================================================================

create extension if not exists pgcrypto;


-- =========================================================================
-- TABELA: customers (cadastro de cliente reaproveitável)
-- Criada ANTES de "rentals" porque "rentals" tem uma coluna que referencia
-- esta tabela (customer_id) — ordem importa ao recriar o banco do zero.
-- =========================================================================
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users(id),
  name text not null,
  document text,
  phone text,
  whatsapp text,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- =========================================================================
-- TABELA: rentals (locações)
-- =========================================================================
create table public.rentals (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users(id),

  -- Dados do cliente (cópia "congelada" no momento da locação — ver
  -- também a tabela "customers" acima, que é o cadastro reaproveitável)
  customer_name text not null,
  document text,
  phone text,
  whatsapp text,
  email text,
  customer_notes text,
  customer_id uuid references public.customers(id) on delete set null, -- link opcional pro cliente-mestre

  -- Dados da locação
  rental_date date,
  expected_return_date date,
  description text,
  rental_notes text,

  -- DEPRECIADO desde a migração de itens múltiplos (migracao-itens.sql):
  -- o app não lê nem escreve mais estas duas colunas — os itens de cada
  -- locação agora vivem em "rental_items". Ficaram aqui só como registro
  -- histórico de locações cadastradas antes dessa mudança. Podem ser
  -- removidas com "alter table rentals drop column ..." no futuro, se
  -- quiser limpar, mas isso é opcional e não urgente.
  equipment_type text,
  quantity text,

  -- Localização da obra
  address text,
  number text,
  complement text,
  neighborhood text,
  city text,
  state text,
  zip_code text,
  location_url text,

  -- Status
  manual_status text,        -- 'encerrada' ou null (demais status são calculados, não gravados)
  closed_at date,            -- data real de encerramento, só preenchida quando manual_status = 'encerrada'
  deleted_at timestamptz,    -- exclusão suave (lixeira); null = ativa, preenchido = na lixeira

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- =========================================================================
-- TABELA: rental_items (itens/tipos de andaime de cada locação — um p/ muitos)
-- =========================================================================
create table public.rental_items (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null references public.rentals(id) on delete cascade,
  equipment_type text not null,
  quantity text,              -- texto livre por escolha de design (ex.: "20 torres");
                               -- se um futuro módulo de Estoque precisar somar quantidades,
                               -- este é o primeiro campo a virar numérico.
  created_at timestamptz not null default now()
);


-- =========================================================================
-- TABELA: equipment_types (catálogo de tipos de andaime, editável no app)
-- =========================================================================
create table public.equipment_types (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users(id),
  name text not null,
  created_at timestamptz not null default now(),
  unique (owner, name)
);


-- =========================================================================
-- TABELA: photos (registros das fotos — os arquivos em si ficam no Storage)
-- =========================================================================
create table public.photos (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null references public.rentals(id) on delete cascade,
  storage_path text not null,  -- caminho no bucket "andaime-fotos", formato: "{rental_id}/{arquivo}"
  description text,
  created_at timestamptz not null default now()
);


-- =========================================================================
-- TABELA: settings (dados da empresa — linha única, id sempre = 1)
-- =========================================================================
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


-- =========================================================================
-- ÍNDICES
-- =========================================================================
create index if not exists idx_customers_name on public.customers
  using gin (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(phone,'') || ' ' || coalesce(document,'')));


-- =========================================================================
-- ROW LEVEL SECURITY — padrão a repetir em qualquer tabela nova/módulo futuro:
-- 1) alter table ... enable row level security;
-- 2) política "for all using (auth.uid() = owner) with check (auth.uid() = owner)"
--    para tabelas com coluna "owner" própria;
-- 3) política via "exists (select 1 from public.rentals r where ...)" para
--    tabelas-filhas que não têm "owner" direto (photos, rental_items).
-- =========================================================================

alter table public.rentals enable row level security;
alter table public.customers enable row level security;
alter table public.rental_items enable row level security;
alter table public.equipment_types enable row level security;
alter table public.photos enable row level security;
alter table public.settings enable row level security;

create policy "owner_all_rentals" on public.rentals for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

create policy "owner_all_customers" on public.customers for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

create policy "owner_all_rental_items" on public.rental_items for all
  using (exists (select 1 from public.rentals r where r.id = rental_id and r.owner = auth.uid()))
  with check (exists (select 1 from public.rentals r where r.id = rental_id and r.owner = auth.uid()));

create policy "owner_all_equipment_types" on public.equipment_types for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

create policy "owner_all_photos" on public.photos for all
  using (exists (select 1 from public.rentals r where r.id = rental_id and r.owner = auth.uid()))
  with check (exists (select 1 from public.rentals r where r.id = rental_id and r.owner = auth.uid()));

create policy "auth_all_settings" on public.settings for all
  using (auth.uid() is not null) with check (auth.uid() is not null);


-- =========================================================================
-- STORAGE — bucket de fotos
-- =========================================================================
-- Criado manualmente pelo painel: Storage > New bucket > nome "andaime-fotos"
-- > Public bucket: OFF. As políticas abaixo são a versão final (já
-- reforçada pela migracao-seguranca-fotos.sql): só permitem mexer numa
-- foto se ela estiver na pasta de uma locação que pertence ao usuário.

create policy "owner_photos_storage_select" on storage.objects for select
  using (
    bucket_id = 'andaime-fotos'
    and exists (
      select 1 from public.rentals r
      where r.id::text = (storage.foldername(name))[1]
      and r.owner = auth.uid()
    )
  );

create policy "owner_photos_storage_insert" on storage.objects for insert
  with check (
    bucket_id = 'andaime-fotos'
    and exists (
      select 1 from public.rentals r
      where r.id::text = (storage.foldername(name))[1]
      and r.owner = auth.uid()
    )
  );

create policy "owner_photos_storage_delete" on storage.objects for delete
  using (
    bucket_id = 'andaime-fotos'
    and exists (
      select 1 from public.rentals r
      where r.id::text = (storage.foldername(name))[1]
      and r.owner = auth.uid()
    )
  );


-- =========================================================================
-- DADOS DE SEED (opcional — só relevante ao recriar o banco do zero)
-- =========================================================================
-- Catálogo inicial de tipos de andaime. Substitua o e-mail abaixo pelo do
-- usuário dono antes de rodar, ou use "select id from auth.users limit 1"
-- se for um banco novo de um único usuário.
--
-- insert into public.equipment_types (owner, name)
-- select (select id from auth.users limit 1), t.name
-- from (values ('Andaime tubular'), ('Andaime fachadeiro'), ('Andaime torre'), ('Andaime suspenso')) as t(name)
-- on conflict do nothing;
