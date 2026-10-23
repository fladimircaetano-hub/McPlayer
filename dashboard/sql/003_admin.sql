-- ============================================================================
-- 003_admin.sql — Administradores do painel
--
-- O 001_schema.sql já promoveu todos os usuários existentes no Auth a admin
-- (fase de teste). Use este script para conferir, adicionar ou remover.
-- Rode no SQL Editor do Supabase.
-- ============================================================================

-- 1) Quem são os admins atuais e quem existe no Auth
select a.email as admin_email, a.active, a.created_at
  from public.admins a
 order by a.created_at;

select u.id, u.email, u.created_at, u.last_sign_in_at,
       (a.user_id is not null) as is_admin
  from auth.users u
  left join public.admins a on a.user_id = u.id
 order by u.created_at;

-- 2) Adicionar um admin pelo e-mail (troque o e-mail)
-- insert into public.admins (user_id, email)
-- select id, email
--   from auth.users
--  where lower(email) = lower('seu-email@exemplo.com')
-- on conflict (user_id) do update set active = true, email = excluded.email;

-- 3) Reativar / desativar sem apagar o usuário
-- update public.admins set active = true  where lower(email) = lower('seu-email@exemplo.com');
-- update public.admins set active = false where lower(email) = lower('seu-email@exemplo.com');

-- 4) Remover o acesso de admin (a conta do Auth continua existindo)
-- delete from public.admins where lower(email) = lower('seu-email@exemplo.com');

-- 5) Se a tabela estiver vazia (primeiro acesso):
--    crie a conta pelo próprio painel (tela de login → "Criar conta"),
--    confirme o e-mail e entre. O RPC claim_admin() promove o primeiro usuário.
