-- 006_xtream_accounts.sql
-- Login por usuário/senha (contas Xtream) + lista de servidores no painel.
--
-- Como rodar: Supabase > SQL Editor > New query > cole este arquivo > Run.
-- Não altera nenhuma tabela existente (apps, devices, playlists, clients,
-- audit_logs continuam iguais).
--
-- O app grava aqui apenas usuário, servidor, aparelho, status e vencimento.
-- A SENHA não é gravada nesta tabela.

-- ---------------------------------------------------------------------------
-- Servidores Xtream (o app testa todos até um aceitar a conta)
-- ---------------------------------------------------------------------------
create table if not exists public.xtream_servers (
  id uuid primary key default gen_random_uuid(),
  app_name text not null default 'McPlayer',
  name text not null,
  url text not null,
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (app_name, url)
);

-- ---------------------------------------------------------------------------
-- Contas que entraram pelo app (somente leitura no painel nesta etapa)
-- ---------------------------------------------------------------------------
create table if not exists public.xtream_clients (
  id uuid primary key default gen_random_uuid(),
  app_name text not null default 'McPlayer',
  username text not null,
  server_url text not null,
  device_id text,
  mac text,
  status text not null default 'active',
  exp_date timestamptz,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (app_name, server_url, username)
);

create index if not exists xtream_clients_last_seen_idx
  on public.xtream_clients (last_seen_at desc);

-- ---------------------------------------------------------------------------
-- Segurança
-- ---------------------------------------------------------------------------
alter table public.xtream_servers enable row level security;
alter table public.xtream_clients enable row level security;

-- O app (chave anon) precisa ler a lista de servidores.
drop policy if exists xtream_servers_read on public.xtream_servers;
create policy xtream_servers_read on public.xtream_servers
  for select using (true);

-- Só administrador do painel cadastra/edita servidores.
drop policy if exists xtream_servers_admin_write on public.xtream_servers;
create policy xtream_servers_admin_write on public.xtream_servers
  for all using (public.is_admin()) with check (public.is_admin());

-- Contas: somente administrador vê/edita. O app grava pela função abaixo.
drop policy if exists xtream_clients_admin on public.xtream_clients;
create policy xtream_clients_admin on public.xtream_clients
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Registro automático do login (chamado pelo app; não guarda senha)
-- ---------------------------------------------------------------------------
create or replace function public.xtream_login_register(
  p_app_name text,
  p_server_url text,
  p_username text,
  p_device_id text default null,
  p_mac text default null,
  p_status text default null,
  p_exp_date timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(trim(p_username), '') = '' or coalesce(trim(p_server_url), '') = '' then
    raise exception 'usuario e servidor sao obrigatorios';
  end if;

  insert into public.xtream_clients (
    app_name, username, server_url, device_id, mac, status, exp_date, last_seen_at
  )
  values (
    coalesce(nullif(trim(p_app_name), ''), 'McPlayer'),
    left(trim(p_username), 120),
    left(trim(p_server_url), 300),
    nullif(trim(p_device_id), ''),
    nullif(trim(p_mac), ''),
    lower(coalesce(nullif(trim(p_status), ''), 'active')),
    p_exp_date,
    now()
  )
  on conflict (app_name, server_url, username) do update
    set device_id = coalesce(excluded.device_id, xtream_clients.device_id),
        mac = coalesce(excluded.mac, xtream_clients.mac),
        status = coalesce(excluded.status, xtream_clients.status),
        exp_date = coalesce(excluded.exp_date, xtream_clients.exp_date),
        last_seen_at = now();
end;
$$;

revoke all on function public.xtream_login_register(text,text,text,text,text,text,timestamptz) from public;
grant execute on function public.xtream_login_register(text,text,text,text,text,text,timestamptz) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Servidores iniciais (edite/adicionar pelo painel depois)
-- ---------------------------------------------------------------------------
insert into public.xtream_servers (app_name, name, url, sort_order)
values
  ('McPlayer', 'Cmax Vision', 'http://cmaxvision.xyz', 10),
  ('McPlayer', 'TV Sirius', 'http://tvsirius.xyz', 20)
on conflict (app_name, url) do nothing;
