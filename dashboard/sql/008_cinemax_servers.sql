-- 008_cinemax_servers.sql
-- Cadastra os DNS da família Cinemax na lista de servidores Xtream dos 3 apps
-- controlados pelo painel: McPlayer, NexPlay e CaetanoPlayer.
--
-- Como rodar: Supabase > SQL Editor > New query > cole este arquivo > Run.
--
-- O app testa os servidores ativos na ordem de sort_order até um aceitar a
-- conta (usuário/senha). O "on conflict" garante nome/ordem/ativo corretos em
-- quem já existir, sem duplicar (a chave única é app_name + url).
--
-- Para incluir um app novo depois, basta duplicar um bloco trocando o app_name.

insert into public.xtream_servers (app_name, name, url, sort_order, active)
values
  -- McPlayer
  ('McPlayer',      'Cmax Vision',   'http://cmaxvision.xyz',   10, true),
  ('McPlayer',      'Cinemax Hub',   'http://cinemaxhub.xyz',   30, true),
  ('McPlayer',      'CinePlus Max',  'http://cineplusmax.xyz',  40, true),
  ('McPlayer',      'Cinemax Ultra', 'http://cinemaxultra.xyz', 50, true),
  ('McPlayer',      'CineFlow Max',  'http://cineflowmax.xyz',  60, true),

  -- NexPlay
  ('NexPlay',       'Cmax Vision',   'http://cmaxvision.xyz',   10, true),
  ('NexPlay',       'Cinemax Hub',   'http://cinemaxhub.xyz',   30, true),
  ('NexPlay',       'CinePlus Max',  'http://cineplusmax.xyz',  40, true),
  ('NexPlay',       'Cinemax Ultra', 'http://cinemaxultra.xyz', 50, true),
  ('NexPlay',       'CineFlow Max',  'http://cineflowmax.xyz',  60, true),

  -- CaetanoPlayer
  ('CaetanoPlayer', 'Cmax Vision',   'http://cmaxvision.xyz',   10, true),
  ('CaetanoPlayer', 'Cinemax Hub',   'http://cinemaxhub.xyz',   30, true),
  ('CaetanoPlayer', 'CinePlus Max',  'http://cineplusmax.xyz',  40, true),
  ('CaetanoPlayer', 'Cinemax Ultra', 'http://cinemaxultra.xyz', 50, true),
  ('CaetanoPlayer', 'CineFlow Max',  'http://cineflowmax.xyz',  60, true)
on conflict (app_name, url) do update
  set name       = excluded.name,
      sort_order = excluded.sort_order,
      active     = excluded.active;

-- Conferir o resultado (agrupado por app):
select app_name, name, url, sort_order, active
from public.xtream_servers
where app_name in ('McPlayer', 'NexPlay', 'CaetanoPlayer')
order by app_name asc, sort_order asc;
