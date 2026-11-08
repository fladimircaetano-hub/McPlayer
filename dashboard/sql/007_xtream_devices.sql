-- 007_xtream_devices.sql
-- Mostra no painel TODOS os aparelhos conectados em cada conta Xtream.
--
-- Como rodar: rode o 006_xtream_accounts.sql primeiro e depois este aqui
-- (Supabase > SQL Editor > New query > cole > Run).
--
-- Antes: `xtream_clients` tinha uma linha por conta (unique app_name +
-- servidor + usuário), então o segundo aparelho que entrava na mesma conta
-- sobrescrevia o primeiro. Agora a linha da conta continua igual e cada
-- aparelho ganha uma linha em `xtream_devices`. O painel lê as duas.

-- ---------------------------------------------------------------------------
-- Aparelhos de cada conta
-- ---------------------------------------------------------------------------
create table if not exists public.xtream_devices (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.xtream_clients(id) on delete cascade,
  device_id text not null,
  mac text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (client_id, device_id)
);

create index if not exists xtream_devices_client_idx
  on public.xtream_devices (client_id, last_seen_at desc);

create index if not exists xtream_devices_last_seen_idx
  on public.xtream_devices (last_seen_at desc);

-- ---------------------------------------------------------------------------
-- Segurança: o app grava pelo RPC; só administrador lê no painel
-- ---------------------------------------------------------------------------
alter table public.xtream_devices enable row level security;

drop policy if exists xtream_devices_admin on public.xtream_devices;
create policy xtream_devices_admin on public.xtream_devices
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Registro automático do login (mesma assinatura da 006, agora grava o
-- aparelho em xtream_devices também)
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
declare
  v_app text := coalesce(nullif(trim(p_app_name), ''), 'McPlayer');
  v_server text := left(trim(p_server_url), 300);
  v_user text := left(trim(p_username), 120);
  v_device text := coalesce(nullif(trim(p_device_id), ''), nullif(trim(p_mac), ''));
  v_mac text := nullif(trim(p_mac), '');
  v_client_id uuid;
begin
  if coalesce(v_user, '') = '' or coalesce(v_server, '') = '' then
    raise exception 'usuario e servidor sao obrigatorios';
  end if;

  insert into public.xtream_clients (
    app_name, username, server_url, device_id, mac, status, exp_date, last_seen_at
  )
  values (
    v_app,
    v_user,
    v_server,
    v_device,
    v_mac,
    lower(coalesce(nullif(trim(p_status), ''), 'active')),
    p_exp_date,
    now()
  )
  on conflict (app_name, server_url, username) do update
    set device_id = coalesce(excluded.device_id, xtream_clients.device_id),
        mac = coalesce(excluded.mac, xtream_clients.mac),
        status = coalesce(excluded.status, xtream_clients.status),
        exp_date = coalesce(excluded.exp_date, xtream_clients.exp_date),
        last_seen_at = now()
  returning id into v_client_id;

  if v_device is not null then
    insert into public.xtream_devices (client_id, device_id, mac, last_seen_at)
    values (v_client_id, left(v_device, 120), v_mac, now())
    on conflict (client_id, device_id) do update
      set mac = coalesce(excluded.mac, xtream_devices.mac),
          last_seen_at = now();
  end if;
end;
$$;

revoke all on function public.xtream_login_register(text,text,text,text,text,text,timestamptz) from public;
grant execute on function public.xtream_login_register(text,text,text,text,text,text,timestamptz) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Aparelhos que já estavam gravados na linha da conta (antes do 007)
-- ---------------------------------------------------------------------------
insert into public.xtream_devices (client_id, device_id, mac, last_seen_at)
select c.id, c.device_id, c.mac, c.last_seen_at
from public.xtream_clients c
where coalesce(trim(c.device_id), '') <> ''
on conflict (client_id, device_id) do update
  set mac = coalesce(nullif(excluded.mac, ''), xtream_devices.mac),
      last_seen_at = greatest(xtream_devices.last_seen_at, excluded.last_seen_at);
