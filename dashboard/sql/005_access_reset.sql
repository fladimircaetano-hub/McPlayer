-- ============================================================================
-- 005_access_reset.sql — Dados extras do aparelho (entrada, cliente e dispositivo)
--
-- Rode este script UMA vez no SQL Editor do Supabase (role postgres), depois
-- de fazer backup pelo painel (Configuração → Baixar backup).
--
-- O que ele faz:
--   1. Cria a coluna devices.start_date ("Data de entrada").
--   2. Cria a coluna devices.client_phone (WhatsApp do cliente), usada para
--      enviar o cadastro automaticamente para a aba Clientes na aprovação.
--   3. Cria as colunas devices.device_type ("Dispositivo em uso": Smartphone,
--      Smart TV, TV Box, Computador, Xbox...) e devices.device_brand
--      (marca/modelo, ex.: Samsung, LG, Fire TV Stick).
--   4. Remove as funções antigas de exclusão em massa, que não são mais usadas.
--
-- Ele NÃO apaga nem altera nenhum aparelho. É seguro rodar mais de uma vez.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Data de entrada do aparelho (editável no painel)
-- ----------------------------------------------------------------------------
alter table public.devices
  add column if not exists start_date date;

comment on column public.devices.start_date is
  'Data de entrada do aparelho/plano. A saída continua em expires_at.';

-- ----------------------------------------------------------------------------
-- 2. WhatsApp do cliente (espelhado em public.clients na aprovação)
-- ----------------------------------------------------------------------------
alter table public.devices
  add column if not exists client_phone text;

comment on column public.devices.client_phone is
  'WhatsApp do cliente. Ao aprovar, o painel cria/atualiza o registro em clients.';

-- ----------------------------------------------------------------------------
-- 3. Dispositivo em uso (tipo físico + marca/modelo)
-- ----------------------------------------------------------------------------
alter table public.devices
  add column if not exists device_type text;

comment on column public.devices.device_type is
  'Dispositivo em uso: Smartphone, Smart TV, TV Box, Computador, Xbox, etc.';

alter table public.devices
  add column if not exists device_brand text;

comment on column public.devices.device_brand is
  'Marca/modelo do dispositivo em uso. Ex.: Samsung, LG, Fire TV Stick.';

-- ----------------------------------------------------------------------------
-- 4. Funções antigas de exclusão em massa (substituídas pela exclusão
--    individual em public.admin_delete_device, criada no 001)
-- ----------------------------------------------------------------------------
drop function if exists public.admin_reset_devices(text);
drop function if exists public.admin_delete_devices(uuid[], text);

commit;

-- ----------------------------------------------------------------------------
-- Conferência
-- ----------------------------------------------------------------------------
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'devices'
   and column_name in ('start_date', 'client_phone', 'device_type', 'device_brand')
 order by column_name;
