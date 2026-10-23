-- ============================================================================
-- 002_cleanup.sql — LIMPEZA DEFINITIVA (rodar SOMENTE após o backup e a
-- confirmação do responsável)
--
-- O que este script apaga:
--   • public.devices_legacy_20261023     (aparelhos antigos)
--   • public.playlists_legacy_20261023   (listas antigas)
--   • public.clients_legacy_20261023     (clientes antigos)
--   • public.device_activations          (log antigo de ativações)
--   • public.audit_logs                  (zerado para começar limpo)
--
-- O que NÃO é apagado:
--   • auth.users (contas de administrador)
--   • public.apps (configuração dos apps)
--   • estrutura/tabelas novas
--
-- Backup usado como referência:
--   dashboard/backups/backup-2026-10-23-16-22-06.json
--   (43 devices, 0 playlists, 0 clients)
-- ============================================================================

begin;

-- 1) Confira os números antes de apagar (devem bater com o backup)
select 'devices_legacy_20261023' as tabela, count(*) as registros
  from public.devices_legacy_20261023
union all
select 'playlists_legacy_20261023', count(*) from public.playlists_legacy_20261023
union all
select 'clients_legacy_20261023',   count(*) from public.clients_legacy_20261023;

-- 2) Log antigo de ativações (estrutura preservada, conteúdo zerado)
do $$
begin
  if to_regclass('public.device_activations') is not null then
    execute 'truncate table public.device_activations';
    raise notice 'device_activations zerada.';
  else
    raise notice 'device_activations não existe; nada a fazer.';
  end if;
end $$;

-- 3) Auditoria começa do zero
truncate table public.audit_logs restart identity;

-- 4) Remove as tabelas antigas (os dados já estão no backup JSON)
drop table if exists public.devices_legacy_20261023 cascade;
drop table if exists public.playlists_legacy_20261023 cascade;
drop table if exists public.clients_legacy_20261023 cascade;

commit;

-- 5) Conferência final
select 'devices'    as tabela, count(*) as registros from public.devices
union all
select 'playlists',  count(*) from public.playlists
union all
select 'clients',    count(*) from public.clients
union all
select 'audit_logs', count(*) from public.audit_logs;
