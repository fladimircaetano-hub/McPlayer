-- ============================================================================
-- 004_rollback.sql — Voltar para as tabelas antigas
--
-- Só funciona ENQUANTO o 002_cleanup.sql não foi executado (as tabelas
-- *_legacy_20261023 ainda existem) e se a tabela nova de devices estiver vazia.
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.devices_legacy_20261023') is null then
    raise exception 'Rollback indisponível: tabelas legadas já foram apagadas.';
  end if;
  if to_regclass('public.devices') is not null
     and exists (select 1 from public.devices) then
    raise exception 'Rollback bloqueado: a tabela nova de devices já tem dados.';
  end if;
end $$;

drop table if exists public.clients   cascade;
drop table if exists public.devices   cascade;
drop table if exists public.playlists cascade;

alter table public.devices_legacy_20261023   rename to devices;
alter table public.playlists_legacy_20261023 rename to playlists;
alter table public.clients_legacy_20261023   rename to clients;

commit;

select 'devices'   as tabela, count(*) as registros from public.devices
union all
select 'playlists', count(*) from public.playlists
union all
select 'clients',   count(*) from public.clients;
