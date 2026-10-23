# Dashboard McPlayer / NexPlay

Painel administrativo estático (HTML + CSS + JS) que fala direto com o
Supabase. Serve os dois apps com o **mesmo código**: a diferença entre
McPlayer e NexPlay é apenas a linha correspondente na tabela `public.apps`
(`code_pattern` / `normalize_upper`).

## Arquivos

| Arquivo | Para que serve |
| --- | --- |
| `index.html` | Estrutura das telas (login, visão geral, aparelhos, listas, clientes, auditoria e configuração). |
| `styles.css` | Tema escuro e layout responsivo. |
| `js/config.js` | URL do Supabase e **anon key** (pública). Nunca coloque a `service_role` aqui. |
| `js/validation.js` | Normalização/validação de código e MAC, geração de código, datas e WhatsApp. |
| `js/api.js` | Única camada de acesso ao Supabase (auth, CRUD, RPCs, realtime e backup). |
| `js/ui.js` | Escaping, modais, toasts, badges e tradução das mensagens de erro. |
| `js/app.js` | Estado, renderização, filtros, formulários e eventos. |
| `sql/001_schema.sql` | Estrutura nova (apps, admins, devices, playlists, clients, auditoria, RLS e RPCs). |
| `sql/002_cleanup.sql` | Limpeza definitiva das tabelas antigas. **Só depois do backup e da confirmação.** |
| `sql/003_admin.sql` | Consultas para conferir/adicionar/remover administradores. |
| `sql/004_rollback.sql` | Volta para as tabelas antigas (somente antes do `002`). |
| `backups/` | Backups JSON locais. **Não versionar** (contém credenciais de listas). |

## Ordem de implantação

1. Faça o backup pelo painel (Configuração → Baixar backup) ou use o JSON em
   `backups/`.
2. No SQL Editor do Supabase, rode **`sql/001_schema.sql`**.
   - Ele renomeia `devices`, `playlists` e `clients` para `*_legacy_20261023`
     e cria as tabelas novas vazias.
   - Promove os usuários existentes do Auth a administradores.
   - Cria as RPCs `device_checkin`, `device_status`, `admin_delete_device`,
     `is_admin` e `claim_admin`.
   - **Não apaga nada.**
3. Teste o painel e o check-in dos apps.
4. Quando estiver tudo certo, com o backup em mãos e **confirmação explícita**
   do responsável, rode **`sql/002_cleanup.sql`**. Ele apaga:
   - `devices_legacy_20261023` (aparelhos antigos);
   - `playlists_legacy_20261023` e `clients_legacy_20261023`;
   - o conteúdo de `device_activations` e de `audit_logs`.

   Ele **não** apaga `auth.users`, `public.apps` nem a estrutura nova.

Se algo der errado antes do `002`, rode `sql/004_rollback.sql`.

## Abrir o painel

Não abra por `file://` se for usar login: o Supabase guarda a sessão no
`localStorage` e alguns navegadores bloqueiam isso em arquivos locais.

```powershell
cd C:\Users\Admini\McPlayer\dashboard
python -m http.server 8765
```

Depois acesse `http://127.0.0.1:8765/`.

Em produção, publique a pasta `dashboard/` inteira (não só o `index.html`).

## Acesso

- **Primeiro acesso:** crie a conta em “Primeiro acesso / criar conta”.
  Confirme o e-mail e entre. Se a tabela `admins` estiver vazia, a primeira
  conta confirmada vira admin (`claim_admin`).
- **Depois:** só entram e-mails presentes em `public.admins` com
  `active = true`. Use `sql/003_admin.sql` para adicionar/remover.
- A `anon key` no navegador é pública. Quem protege os dados é o RLS +
  `public.is_admin()`. A `service_role` nunca vai para o frontend.

## Checklist de teste

1. **Login**
   - Entrar com a conta admin.
   - Tentar entrar com uma conta que não está em `admins` (deve recusar).
2. **Aparelhos**
   - Criar aparelho McPlayer com código numérico de 6 dígitos.
   - Criar aparelho NexPlay com código alfanumérico de 6 caracteres em
     minúsculas; conferir que foi salvo em MAIÚSCULAS.
   - Tentar código inválido (letras no McPlayer / 5 caracteres) e conferir a
     mensagem.
   - Repetir o mesmo código no mesmo app (deve recusar) e no outro app
     (deve permitir).
   - Vincular MAC com hífen/minúsculo e conferir o formato
     `AA:BB:CC:DD:EE:FF`.
   - Repetir o mesmo MAC no mesmo app (deve recusar).
   - Desvincular o MAC, salvar e conferir que o código continua funcionando.
   - Buscar por código parcial e por MAC parcial.
   - Bloquear e liberar; conferir o motivo do bloqueio.
   - Excluir digitando o código exato (o botão só habilita com o código certo).
3. **Listas**
   - Criar lista M3U e lista Xtream.
   - Editar e excluir (com confirmação).
   - Vincular uma lista a um aparelho e conferir que os campos são preenchidos.
4. **Clientes**
   - Criar cliente vinculado a um aparelho.
   - Usar “+30 dias” e o atalho de WhatsApp.
   - Excluir o cliente.
5. **Tempo real**
   - Abrir o painel em duas abas e alterar um aparelho em uma delas; a outra
     deve atualizar sozinha (Realtime + polling de 20 s).
6. **Auditoria**
   - Conferir inserir/editar/excluir/bloquear/liberar/vincular MAC.
   - Abrir “Ver antes/depois” e filtrar por app, ação e busca.
7. **Configuração**
   - Criar um terceiro app com outra regex e conferir que ele aparece nos
     filtros e no formulário sem alterar o código.
   - Editar e excluir um app sem registros (apps em uso são protegidos).
   - Baixar o backup JSON.

## Recadastrar os aparelhos

1. Rode o `001_schema.sql` (as tabelas novas começam vazias).
2. Gere um APK novo. O check-in agora usa as RPCs `device_checkin` /
   `device_status`; o APK antigo (acesso direto à tabela `devices`) deixa de
   funcionar quando o RLS novo entra em vigor.
   ```powershell
   flutter build apk --release --split-per-abi `
     --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co `
     --dart-define=SUPABASE_ANON_KEY=SUA-ANON-KEY `
     --dart-define=APP_NAME=McPlayer
   ```
   Para o NexPlay, troque apenas `APP_NAME=NexPlay`.
3. Abra o app: ele gera a chave e aparece em **Aparelhos → Pendentes**.
4. No painel, edite o aparelho, vincule uma lista (M3U ou Xtream) e aprove.
5. O app recebe a lista no próximo polling (10 a 30 segundos, com backoff).
6. Se o aparelho não enviar MAC, o código continua valendo; vincule o MAC
   manualmente depois, se quiser.
7. O MAC enviado pelo app é usado apenas no **primeiro** check-in. Depois
   disso, editar ou desvincular o MAC pelo painel prevalece e o app não
   sobrescreve mais esse campo.

## Observações

- O painel não executa DDL. Os scripts SQL são rodados manualmente no SQL
  Editor do Supabase, com confirmação antes do `002`.
- A gestão de aparelhos agora é feita por este painel. A tela Admin antiga
  dentro do app usava acesso anônimo direto na tabela `devices` e deixa de
  funcionar com o RLS novo.
- A pasta `backups/` e o `devices.json` estão no `.gitignore` porque contêm
  usuários/senhas de listas.
