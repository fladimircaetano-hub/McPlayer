# Próximos passos — Dashboard McPlayer (continuar amanhã)

Data: 22/09/2026
Objetivo: lista à mostra em cada dispositivo; lápis só para editar.

## Estado atual
- GitHub `main` = `f2bff15` (tem a v1 + arquivo stray `dashboard-playlist.patch`).
- Patch v3 pronto em `C:\Users\Admini\McPlayer\dashboard-lista-visivel.patch`:
  - Bloco "Lista do aparelho" + "Vincular e aprovar" nos cards pendentes.
  - "Trocar lista" + "Salvar e enviar" nos detalhes dos aprovados.
  - Lápis abre modal pré-preenchido ("Editar Lista do Dispositivo").
  - Remove `dashboard-playlist.patch` do repo.
- App Flutter (McPlayer): fluxo Dashboard -> aparelho OK (polling a cada 10s, testes passando).

## Passo a passo pendente (GitHub Desktop, repo Dashboard-Mc-Player)
1. Changes → Discard all (limpar pendências locais).
2. Fetch origin / Pull até estar no `f2bff15`.
3. Apagar arquivos `.patch` locais da pasta do repo.
4. Copiar SÓ `C:\Users\Admini\McPlayer\dashboard-lista-visivel.patch` para a pasta.
5. Repository → Open in Command Prompt:
   - `git apply --check dashboard-lista-visivel.patch`
   - `git apply dashboard-lista-visivel.patch`
6. Conferir 2 arquivos alterados + 1 exclusão (`DeviceApprovalModal.tsx`, `Devices.tsx`, del `dashboard-playlist.patch`).
7. Apagar o `.patch` da pasta.
8. Summary: `Lista a mostra por dispositivo (vinculo inline) + lapis edita`
9. Commit to main (Override se o Copilot reclamar) → Push origin.
10. Aguardar 2-3 min → conferir `https://dashboard-mc-player.vercel.app/` (Ctrl+Shift+R).

## Depois (se der tempo)
- Criar tabela `playlists` no Supabase se ainda não existir
  (`id, name, type, url, server_url, username, password`).
- Teste fim a fim: cadastrar lista → vincular num pendente → app recebe sozinho.
- Revisar `.env` da Vercel (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`).
