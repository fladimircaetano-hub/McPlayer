-- ============================================================================
-- McPlayer / NexPlay — Dashboard administrativo
-- 001_schema.sql — Estrutura nova (código + MAC, apps configuráveis, auditoria)
--
-- IMPORTANTE
--   1. Rode este script no SQL Editor do Supabase (role postgres/service_role).
--   2. Ele NÃO apaga os dados antigos: renomeia as tabelas atuais para
--      *_legacy_20261023. A limpeza definitiva fica no 002_cleanup.sql.
--   3. Faça o backup antes (dashboard/backups/backup-*.json).
-- ============================================================================

begin;

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 0. Preserva as tabelas antigas (rollback possível até rodar o 002)
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.devices') is not null
     and to_regclass('public.devices_legacy_20261023') is null then
    alter table public.devices rename to devices_legacy_20261023;
  end if;

  if to_regclass('public.playlists') is not null
     and to_regclass('public.playlists_legacy_20261023') is null then
    alter table public.playlists rename to playlists_legacy_20261023;
  end if;

  if to_regclass('public.clients') is not null
     and to_regclass('public.clients_legacy_20261023') is null then
    alter table public.clients rename to clients_legacy_20261023;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 1. Apps: a regra de código vem do banco, não do frontend
--    Um app novo = uma linha nova nesta tabela.
-- ----------------------------------------------------------------------------
create table if not exists public.apps (
  name            text primary key,
  code_pattern    text not null,
  code_hint       text not null default '',
  normalize_upper boolean not null default true,
  active          boolean not null default true,
  sort_order      integer not null default 100,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Evita "McPlayer" e "mcplayer" como apps diferentes (o check-in busca por
-- lower(name), então nomes repetidos em caixas diferentes seriam ambíguos).
create unique index if not exists apps_name_lower_key
  on public.apps (lower(name));

insert into public.apps (name, code_pattern, code_hint, normalize_upper, sort_order)
values
  ('McPlayer', '^[0-9]{6}$',    '6 dígitos numéricos (0-9)', false, 10),
  ('NexPlay',  '^[A-Z0-9]{6}$', '6 caracteres: letras A-Z e números 0-9', true, 20)
on conflict (name) do update
  set code_pattern    = excluded.code_pattern,
      code_hint       = excluded.code_hint,
      normalize_upper = excluded.normalize_upper,
      sort_order      = excluded.sort_order,
      updated_at      = now();

create or replace function public.apps_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.name         := btrim(new.name);
  new.code_pattern := btrim(new.code_pattern);
  new.code_hint    := btrim(coalesce(new.code_hint, ''));

  if new.name = '' then
    raise exception 'Nome do app é obrigatório.' using errcode = '22023';
  end if;
  if new.code_pattern = '' then
    raise exception 'O padrão (regex) do código é obrigatório.' using errcode = '22023';
  end if;

  -- Valida a regex no banco (evita salvar uma regra que quebra o check-in)
  begin
    perform ('' ~ new.code_pattern);
  exception when invalid_regular_expression then
    raise exception 'Regex inválida para o app %: %', new.name, new.code_pattern
      using errcode = '22023';
  end;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists apps_before_write on public.apps;
create trigger apps_before_write
  before insert or update on public.apps
  for each row execute function public.apps_before_write();

-- ----------------------------------------------------------------------------
-- 2. Administradores (usuários do Supabase Auth com permissão de admin)
-- ----------------------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists admins_email_lower_key
  on public.admins (lower(email));

-- Preserva quem já existe no Auth. Em fase de teste, todos os usuários
-- existentes são o(s) administrador(es) do painel.
-- (Se houver usuários que NÃO são admin, remova-os depois com 003_admin.sql.)
insert into public.admins (user_id, email)
select u.id, u.email
  from auth.users u
 where u.email is not null
on conflict (user_id) do nothing;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.admins a
     where a.user_id = auth.uid()
       and a.active
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- Bootstrap: se a tabela de admins estiver vazia, o primeiro usuário
-- autenticado que entrar vira admin. Depois disso, ninguém entra sozinho.
create or replace function public.claim_admin()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := coalesce(auth.jwt() ->> 'email', '');
  v_count integer;
begin
  if v_uid is null then
    return false;
  end if;

  select count(*) into v_count from public.admins;
  if v_count > 0 then
    return public.is_admin();
  end if;

  insert into public.admins (user_id, email)
  values (v_uid, coalesce(nullif(v_email, ''), 'admin-' || v_uid::text))
  on conflict (user_id) do nothing;

  return true;
end;
$$;

revoke all on function public.claim_admin() from public;
grant execute on function public.claim_admin() to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Listas (biblioteca de playlists, dinâmica por app)
-- ----------------------------------------------------------------------------
create table if not exists public.playlists (
  id         uuid primary key default gen_random_uuid(),
  app_name   text not null references public.apps(name) on update cascade,
  name       text not null,
  type       text not null check (type in ('m3u', 'xtream')),
  url        text,
  server_url text,
  username   text,
  password   text,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint playlists_name_not_blank check (btrim(name) <> ''),
  constraint playlists_fields check (
    (type = 'm3u'
      and url is not null and btrim(url) <> '')
    or
    (type = 'xtream'
      and server_url is not null and btrim(server_url) <> ''
      and username is not null and btrim(username) <> ''
      and password is not null and btrim(password) <> '')
  )
);

create unique index if not exists playlists_app_name_key
  on public.playlists (app_name, lower(name));

create or replace function public.playlists_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.name       := btrim(new.name);
  new.notes      := nullif(btrim(coalesce(new.notes, '')), '');
  new.url        := nullif(btrim(coalesce(new.url, '')), '');
  new.server_url := nullif(btrim(coalesce(new.server_url, '')), '');
  new.username   := nullif(btrim(coalesce(new.username, '')), '');
  new.password   := nullif(new.password, '');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists playlists_before_write on public.playlists;
create trigger playlists_before_write
  before insert or update on public.playlists
  for each row execute function public.playlists_before_write();

-- ----------------------------------------------------------------------------
-- 4. Aparelhos (código principal + MAC opcional, sem perder histórico)
-- ----------------------------------------------------------------------------
create table if not exists public.devices (
  id           uuid primary key default gen_random_uuid(),
  app_name     text not null references public.apps(name) on update cascade,
  device_id    text not null,
  mac          text,
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'blocked')),
  list_data    jsonb,
  playlist_id  uuid references public.playlists(id) on delete set null,
  client_name  text,
  expires_at   date,
  notes        text,
  block_reason text,
  approved_at  timestamptz,
  blocked_at   timestamptz,
  request_date timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint devices_code_not_blank check (btrim(device_id) <> ''),
  constraint devices_mac_format check (
    mac is null or mac ~ '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
  )
);

-- Código único DENTRO do app. O mesmo código pode existir em apps diferentes.
create unique index if not exists devices_app_code_key
  on public.devices (app_name, device_id);

-- MAC único DENTRO do app (MAC nulo não participa do índice).
create unique index if not exists devices_app_mac_key
  on public.devices (app_name, mac)
  where mac is not null;

create index if not exists devices_app_status_idx
  on public.devices (app_name, status);

create index if not exists devices_created_idx
  on public.devices (created_at desc);

-- Validação central: regex do app, normalização de maiúsculas e MAC.
create or replace function public.devices_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  a        public.apps%rowtype;
  v_mac    text;
begin
  select * into a
    from public.apps
   where name = new.app_name;

  if not found then
    raise exception 'App "%" não cadastrado.', new.app_name
      using errcode = '22023';
  end if;

  -- Check-in (anon) só entra em app ativo. O admin ainda pode editar/limpar
  -- aparelhos antigos de um app que foi desativado.
  if not a.active and not public.is_admin() then
    raise exception 'App "%" está inativo.', new.app_name
      using errcode = '22023';
  end if;

  new.device_id := btrim(new.device_id);
  if a.normalize_upper then
    new.device_id := upper(new.device_id);
  end if;

  if new.device_id !~ a.code_pattern then
    raise exception 'Código inválido para %: %', a.name, a.code_hint
      using errcode = '22023';
  end if;

  if new.mac is not null then
    v_mac := upper(regexp_replace(new.mac, '[^0-9A-Fa-f]', '', 'g'));
    if length(v_mac) <> 12 then
      raise exception 'MAC inválido. Use 12 dígitos hexadecimais (AA:BB:CC:DD:EE:FF).'
        using errcode = '22023';
    end if;
    new.mac := substr(v_mac, 1, 2) || ':' || substr(v_mac, 3, 2) || ':' ||
               substr(v_mac, 5, 2) || ':' || substr(v_mac, 7, 2) || ':' ||
               substr(v_mac, 9, 2) || ':' || substr(v_mac, 11, 2);
  end if;

  new.client_name  := nullif(btrim(coalesce(new.client_name, '')), '');
  new.notes        := nullif(btrim(coalesce(new.notes, '')), '');
  new.block_reason := nullif(btrim(coalesce(new.block_reason, '')), '');
  new.updated_at   := now();

  if tg_op = 'INSERT' then
    new.created_at   := coalesce(new.created_at, now());
    new.request_date := coalesce(new.request_date, now());
  end if;

  if new.status = 'approved' then
    if new.approved_at is null then
      new.approved_at := now();
    end if;
    new.blocked_at := null;
  elsif new.status = 'blocked' then
    if new.blocked_at is null then
      new.blocked_at := now();
    end if;
  else
    new.approved_at := null;
    new.blocked_at  := null;
  end if;

  return new;
end;
$$;

drop trigger if exists devices_before_write on public.devices;
create trigger devices_before_write
  before insert or update on public.devices
  for each row execute function public.devices_before_write();

-- ----------------------------------------------------------------------------
-- 5. Clientes (vinculados por app + código; o aparelho pode ser trocado)
-- ----------------------------------------------------------------------------
create table if not exists public.clients (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  phone      text not null,
  app_name   text references public.apps(name) on update cascade,
  device_id  text,
  expires_at date,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_name_not_blank check (btrim(name) <> ''),
  constraint clients_phone_not_blank check (btrim(phone) <> ''),
  constraint clients_device_fk
    foreign key (app_name, device_id)
    references public.devices (app_name, device_id)
    on update cascade
    on delete set null
);

create index if not exists clients_app_device_idx
  on public.clients (app_name, device_id);

create or replace function public.clients_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.name       := btrim(new.name);
  new.phone      := btrim(new.phone);
  new.device_id  := nullif(btrim(coalesce(new.device_id, '')), '');
  new.notes      := nullif(btrim(coalesce(new.notes, '')), '');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists clients_before_write on public.clients;
create trigger clients_before_write
  before insert or update on public.clients
  for each row execute function public.clients_before_write();

-- ----------------------------------------------------------------------------
-- 6. Auditoria (append-only, com antes/depois)
-- ----------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  actor_id    uuid,
  actor_email text,
  source      text not null default 'dashboard',
  entity      text not null default 'device',
  action      text not null,
  app_name    text,
  device_id   text,
  mac         text,
  before      jsonb,
  after       jsonb
);

create index if not exists audit_logs_created_idx
  on public.audit_logs (created_at desc);
create index if not exists audit_logs_app_idx
  on public.audit_logs (app_name, created_at desc);
create index if not exists audit_logs_action_idx
  on public.audit_logs (action, created_at desc);
create index if not exists audit_logs_mac_idx
  on public.audit_logs (mac, created_at desc);

create or replace function public.audit_devices()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text;
  v_email  text;
  v_source text;
  v_actor  uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    v_action := 'insert';
  elsif tg_op = 'DELETE' then
    v_action := 'delete';
  else
    if new.mac is distinct from old.mac then
      v_action := case
        when new.mac is null then 'unlink_mac'
        when old.mac is null then 'link_mac'
        else 'change_mac'
      end;
    elsif new.status is distinct from old.status then
      v_action := case
        when new.status = 'blocked' then 'block'
        when old.status = 'blocked' then 'unblock'
        when new.status = 'approved' then 'approve'
        else 'update'
      end;
    elsif new.device_id is distinct from old.device_id then
      v_action := 'change_code';
    elsif new.list_data is distinct from old.list_data
       or new.playlist_id is distinct from old.playlist_id then
      v_action := 'list_change';
    else
      v_action := 'update';
    end if;
  end if;

  v_email := coalesce(
    nullif(current_setting('app.actor', true), ''),
    nullif(auth.jwt() ->> 'email', ''),
    'sistema'
  );
  v_source := coalesce(nullif(current_setting('app.source', true), ''), 'dashboard');

  insert into public.audit_logs
    (actor_id, actor_email, source, entity, action, app_name, device_id, mac, before, after)
  values (
    v_actor,
    v_email,
    v_source,
    'device',
    v_action,
    case when tg_op = 'DELETE' then old.app_name else new.app_name end,
    case when tg_op = 'DELETE' then old.device_id else new.device_id end,
    case when tg_op = 'DELETE' then old.mac else new.mac end,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists devices_audit on public.devices;
create trigger devices_audit
  after insert or update or delete on public.devices
  for each row execute function public.audit_devices();

-- Auditoria de listas e clientes (todas as ações do painel)
create or replace function public.audit_entity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity text := tg_argv[0];
  v_action text := lower(tg_op);
  v_before jsonb;
  v_after  jsonb;
  v_app    text;
begin
  if tg_op <> 'INSERT' then v_before := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_after  := to_jsonb(new); end if;
  -- `apps` não tem app_name: o próprio nome do app é o app do evento.
  -- Evita tocar em NEW no DELETE e em OLD no INSERT.
  if v_entity = 'app' then
    if tg_op = 'DELETE' then v_app := old.name; else v_app := new.name; end if;
  elsif tg_op = 'INSERT' then
    v_app := to_jsonb(new)->>'app_name';
  elsif tg_op = 'DELETE' then
    v_app := to_jsonb(old)->>'app_name';
  else
    v_app := coalesce(to_jsonb(new)->>'app_name', to_jsonb(old)->>'app_name');
  end if;

  insert into public.audit_logs
    (actor_id, actor_email, source, entity, action, app_name, device_id, mac, before, after)
  values (
    auth.uid(),
    coalesce(
      nullif(current_setting('app.actor', true), ''),
      nullif(auth.jwt() ->> 'email', ''),
      'sistema'
    ),
    coalesce(nullif(current_setting('app.source', true), ''), 'dashboard'),
    v_entity,
    v_action,
    v_app,
    null,
    null,
    v_before,
    v_after
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists playlists_audit on public.playlists;
create trigger playlists_audit
  after insert or update or delete on public.playlists
  for each row execute function public.audit_entity('playlist');

drop trigger if exists clients_audit on public.clients;
create trigger clients_audit
  after insert or update or delete on public.clients
  for each row execute function public.audit_entity('client');

drop trigger if exists apps_audit on public.apps;
create trigger apps_audit
  after insert or update or delete on public.apps
  for each row execute function public.audit_entity('app');

-- ----------------------------------------------------------------------------
-- 7. RLS / permissões
--    anon  = apps (check-in/status) via RPC, sem acesso direto às tabelas
--    authenticated = admin (validado por public.is_admin())
-- ----------------------------------------------------------------------------
alter table public.apps       enable row level security;
alter table public.admins     enable row level security;
alter table public.devices    enable row level security;
alter table public.playlists  enable row level security;
alter table public.clients    enable row level security;
alter table public.audit_logs enable row level security;

-- apps: leitura pública (nome/regra), escrita só admin
drop policy if exists apps_read on public.apps;
create policy apps_read on public.apps
  for select to anon, authenticated
  using (true);

drop policy if exists apps_admin_write on public.apps;
create policy apps_admin_write on public.apps
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke insert, update, delete on public.apps from anon;
grant select on public.apps to anon;

-- admins: cada admin vê a lista; ninguém altera pelo painel
drop policy if exists admins_read on public.admins;
create policy admins_read on public.admins
  for select to authenticated
  using (public.is_admin() or user_id = auth.uid());

-- devices: somente admin. DELETE só via RPC admin_delete_device (confirmação).
drop policy if exists devices_admin_select on public.devices;
create policy devices_admin_select on public.devices
  for select to authenticated
  using (public.is_admin());

drop policy if exists devices_admin_insert on public.devices;
create policy devices_admin_insert on public.devices
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists devices_admin_update on public.devices;
create policy devices_admin_update on public.devices
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke all on public.devices from anon;
revoke delete on public.devices from authenticated;

-- playlists: admin
drop policy if exists playlists_admin_all on public.playlists;
create policy playlists_admin_all on public.playlists
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke all on public.playlists from anon;

-- clients: admin
drop policy if exists clients_admin_all on public.clients;
create policy clients_admin_all on public.clients
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke all on public.clients from anon;

-- auditoria: apenas leitura por admin. Append-only (sem update/delete).
drop policy if exists audit_admin_read on public.audit_logs;
create policy audit_admin_read on public.audit_logs
  for select to authenticated
  using (public.is_admin());

revoke all on public.admins from anon;
revoke all on public.audit_logs from anon;
revoke insert, update, delete on public.audit_logs from authenticated;

-- Grants explícitos. O Supabase já aplica default privileges, mas não
-- dependemos disso: sem estes grants o painel autenticado não lê/escreve.
grant usage on schema public to anon, authenticated;

grant select on public.apps to anon;
grant select, insert, update, delete on public.apps to authenticated;

grant select on public.admins to authenticated;

-- DELETE de devices é só pelo RPC admin_delete_device().
grant select, insert, update on public.devices to authenticated;

grant select, insert, update, delete on public.playlists to authenticated;
grant select, insert, update, delete on public.clients to authenticated;

grant select on public.audit_logs to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ----------------------------------------------------------------------------
-- 8. Exclusão de aparelho com confirmação (RPC)
--    O frontend precisa digitar o código exato; o banco confere de novo.
-- ----------------------------------------------------------------------------
create or replace function public.admin_delete_device(p_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.devices%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Sem permissão de administrador.' using errcode = '42501';
  end if;

  select * into d
    from public.devices
   where id = p_id
   for update;

  if not found then
    raise exception 'Aparelho não encontrado.' using errcode = 'P0002';
  end if;

  if upper(btrim(coalesce(p_code, ''))) <> upper(d.device_id) then
    raise exception 'Confirmação inválida: digite o código exato do aparelho.'
      using errcode = '22023';
  end if;

  perform set_config('app.source', 'dashboard', true);
  delete from public.devices where id = p_id;
  return true;
end;
$$;

revoke all on function public.admin_delete_device(uuid, text) from public;
grant execute on function public.admin_delete_device(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. Check-in dos apps (anon) — validação/normalização no banco
--    Substitui o INSERT/SELECT direto que o app fazia na tabela devices.
-- ----------------------------------------------------------------------------
create or replace function public.device_checkin(
  p_app  text,
  p_code text,
  p_mac  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a       public.apps%rowtype;
  d       public.devices%rowtype;
  v_code  text := btrim(coalesce(p_code, ''));
  v_mac   text;
begin
  select * into a
    from public.apps
   where lower(name) = lower(btrim(coalesce(p_app, '')))
     and active;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_app');
  end if;

  if a.normalize_upper then
    v_code := upper(v_code);
  end if;

  if v_code !~ a.code_pattern then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'hint', a.code_hint);
  end if;

  if p_mac is not null and btrim(p_mac) <> '' then
    v_mac := upper(regexp_replace(p_mac, '[^0-9A-Fa-f]', '', 'g'));
    if length(v_mac) = 12 then
      v_mac := substr(v_mac, 1, 2) || ':' || substr(v_mac, 3, 2) || ':' ||
               substr(v_mac, 5, 2) || ':' || substr(v_mac, 7, 2) || ':' ||
               substr(v_mac, 9, 2) || ':' || substr(v_mac, 11, 2);
    else
      v_mac := null; -- MAC inválido não bloqueia o aparelho
    end if;
  end if;

  perform set_config('app.source', 'activation', true);
  perform set_config('app.actor', 'app:' || a.name, true);

  select * into d
    from public.devices
   where app_name = a.name
     and device_id = v_code
   for update;

  if not found then
    if v_mac is not null then
      -- O mesmo MAC não pode ficar em dois aparelhos do mesmo app.
      update public.devices
         set mac = null
       where app_name = a.name
         and mac = v_mac;
    end if;

    insert into public.devices (app_name, device_id, mac, status)
    values (a.name, v_code, v_mac, 'pending')
    returning * into d;
  end if;

  -- O MAC do app é capturado no primeiro check-in. Depois disso, o painel
  -- manda: editar/desvincular MAC no dashboard não é desfeito pelo app.

  return jsonb_build_object(
    'ok', true,
    'status', d.status,
    'list_data', d.list_data,
    'approved_at', d.approved_at,
    'app_name', d.app_name,
    'device_id', d.device_id,
    'mac', d.mac
  );

exception when unique_violation then
  -- Corrida entre dois check-ins: relê o registro vencedor.
  select * into d
    from public.devices
   where app_name = a.name
     and device_id = v_code;

  if found then
    return jsonb_build_object(
      'ok', true,
      'status', d.status,
      'list_data', d.list_data,
      'approved_at', d.approved_at,
      'app_name', d.app_name,
      'device_id', d.device_id,
      'mac', d.mac
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'conflict');
end;
$$;

revoke all on function public.device_checkin(text, text, text) from public;
grant execute on function public.device_checkin(text, text, text) to anon, authenticated;

-- Polling do app: devolve só o necessário (status/lista), sem exigir SELECT.
create or replace function public.device_status(p_app text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a      public.apps%rowtype;
  d      public.devices%rowtype;
  v_code text := btrim(coalesce(p_code, ''));
begin
  select * into a
    from public.apps
   where lower(name) = lower(btrim(coalesce(p_app, '')))
     and active;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_app');
  end if;

  if a.normalize_upper then
    v_code := upper(v_code);
  end if;

  if v_code !~ a.code_pattern then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'hint', a.code_hint);
  end if;

  select * into d
    from public.devices
   where app_name = a.name
     and device_id = v_code;

  if not found then
    return jsonb_build_object('ok', true, 'status', 'not_found', 'app_name', a.name);
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', d.status,
    'list_data', d.list_data,
    'approved_at', d.approved_at,
    'app_name', d.app_name,
    'device_id', d.device_id,
    'mac', d.mac
  );
end;
$$;

revoke all on function public.device_status(text, text) from public;
grant execute on function public.device_status(text, text) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 10. Realtime (sem recarregar a página)
-- ----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'devices'
    ) then
      alter publication supabase_realtime add table public.devices;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'playlists'
    ) then
      alter publication supabase_realtime add table public.playlists;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'clients'
    ) then
      alter publication supabase_realtime add table public.clients;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'audit_logs'
    ) then
      alter publication supabase_realtime add table public.audit_logs;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'apps'
    ) then
      alter publication supabase_realtime add table public.apps;
    end if;
  end if;
end $$;

commit;

-- Resumo do que ficou preservado (ainda sem apagar nada)
select 'apps'         as tabela, count(*) as registros from public.apps
union all
select 'admins',       count(*) from public.admins
union all
select 'devices',      count(*) from public.devices
union all
select 'playlists',    count(*) from public.playlists
union all
select 'clients',      count(*) from public.clients
union all
select 'audit_logs',   count(*) from public.audit_logs;

do $$
begin
  if to_regclass('public.devices_legacy_20261023') is not null then
    raise notice 'Legado devices: % registro(s)',
      (select count(*) from public.devices_legacy_20261023);
  end if;
  if to_regclass('public.playlists_legacy_20261023') is not null then
    raise notice 'Legado playlists: % registro(s)',
      (select count(*) from public.playlists_legacy_20261023);
  end if;
  if to_regclass('public.clients_legacy_20261023') is not null then
    raise notice 'Legado clients: % registro(s)',
      (select count(*) from public.clients_legacy_20261023);
  end if;
end $$;
