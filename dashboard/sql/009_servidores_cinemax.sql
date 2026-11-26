-- 009_servidores_cinemax.sql
-- Deixa somente os 5 servidores Cinemax nos 3 apps do painel
-- (McPlayer, NexPlay e CaetanoPlayer) e remove o TV Sirius de todos.
--
-- Como rodar: Supabase > SQL Editor > New query > cole este arquivo > Run.
-- Pode rodar mais de uma vez (idempotente).

-- 1) Remove o TV Sirius de todos os apps (por URL e por nome, por segurança).
delete from public.xtream_servers
where lower(btrim(url)) in ('http://tvsirius.xyz', 'https://tvsirius.xyz')
   or lower(btrim(name)) = 'tv sirius';

-- 2) Garante que os 3 apps só tenham os 5 servidores Cinemax.
delete from public.xtream_servers
where app_name in ('McPlayer', 'NexPlay', 'CaetanoPlayer')
  and lower(btrim(url)) not in (
    'http://cmaxvision.xyz',
    'http://cinemaxhub.xyz',
    'http://cineplusmax.xyz',
    'http://cinemaxultra.xyz',
    'http://cineflowmax.xyz'
  );

-- 3) Renumera a ordem de teste para 10, 20, 30, 40, 50 em cada app.
update public.xtream_servers s
set sort_order = v.ord
from (values
  ('http://cmaxvision.xyz',  10),
  ('http://cinemaxhub.xyz',  20),
  ('http://cineplusmax.xyz', 30),
  ('http://cinemaxultra.xyz', 40),
  ('http://cineflowmax.xyz', 50)
) as v(url, ord)
where lower(btrim(s.url)) = v.url
  and s.app_name in ('McPlayer', 'NexPlay', 'CaetanoPlayer');

-- 4) Conferir: devem aparecer 15 linhas (5 x 3 apps), sem TV Sirius.
select app_name, name, url, sort_order, active
from public.xtream_servers
where app_name in ('McPlayer', 'NexPlay', 'CaetanoPlayer')
order by app_name asc, sort_order asc;
