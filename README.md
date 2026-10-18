# LabScheduler v0.7 — GitHub Pages + Google Apps Script (sem Supabase)

O site **permanece em** https://ippn-ufrj.github.io/LabScheduler/ . Login e reservas usam um aplicativo Google Apps Script incorporado em `Nova reserva` (iframe). **Não há senha no GitHub nem conta GitHub obrigatória para os pesquisadores.**

## Instalação obrigatória — uma única vez pelo administrador

1. Abra https://script.google.com/ e crie **Novo projeto** com uma conta Google administrativa institucional. Defina o fuso horário do projeto como `America/Sao_Paulo`.
2. No editor, substitua `Code.gs` pelo conteúdo de `apps-script/Code.gs`. Crie um segundo arquivo **Script** chamado `Equipment` e cole `apps-script/Equipment.gs`. Crie um arquivo **HTML** chamado `Index` e cole `apps-script/Index.html`.
3. Em **Project Settings → Script Properties**, configure:
   - `ADMIN_USERNAME`: por exemplo `ricardo_mborges`.
   - `ADMIN_PASSWORD`: uma senha inicial **nova e forte**, com pelo menos 12 caracteres; não use senha do Faces.
   - `PASSWORD_PEPPER`: um segredo aleatório longo (mínimo 32 caracteres) que não deve ir para o GitHub.
   - `SHEET_ID`: deixe vazio inicialmente. A função `setup()` criará uma planilha privada.
4. No editor, selecione a função `setup` e clique em **Run**. Autorize a criação da planilha Google privada. A função remove `ADMIN_PASSWORD` das propriedades após criar o administrador. Copie o URL da planilha do registro de execução. Não publique a planilha.
5. Clique em **Deploy → New deployment → Web app**. Escolha **Execute as: Me** e **Who has access: Anyone**. Isso não publica as planilhas: todas as operações de leitura e escrita passam por autenticação no servidor. Copie a URL `/exec` da implantação.
6. No repositório GitHub, abra **Settings → Secrets and variables → Actions → Variables** e adicione `VITE_APPS_SCRIPT_URL` com a URL `/exec`.
7. Envie o conteúdo deste ZIP à raiz do repositório `IPPN-UFRJ/LabScheduler` (incluindo `.github/workflows/deploy.yml`) e execute **Actions → Deploy LabScheduler → Run workflow**. Abra o site, clique **Entrar** e use o usuário e a senha definidos no passo 3.
8. Dentro do painel administrativo, **adicione um projeto** e depois cadastre os usuários. Para autorizar todos os equipamentos/projetos, use `*`. Para restringir, use os códigos PNIPE e IDs separados por vírgula.

## Funcionamento

- O usuário entra com **nome de usuário + senha** no formulário incorporado ao site.
- O calendário semanal apresenta blocos de 1 hora, das 07h às 19h. Clique no primeiro e no último bloco consecutivo do mesmo dia. A reserva é confirmada após validação no servidor, sob `LockService` para reduzir conflitos concorrentes.
- O administrador cria usuários, define permissões e ativa/desativa contas. Nenhum cadastro público é permitido.
- O backend registra as reservas na planilha Google **privada** e não no JSON público do GitHub.
- A lista anterior de 118 usuários do Faces pode ser migrada depois; **não** publique o CSV de e-mails ou senhas no GitHub. Nomes Faces podem ser reutilizados, com novas senhas iniciais.

## Limitações e segurança

**Esta é uma implementação piloto, não uma implantação de produção auditada.** O Apps Script tem quotas e restrições de incorporação por iframe; alguns navegadores podem bloquear conteúdo de terceiros. Nesse caso, abra a URL `/exec` diretamente para operar a reserva. A interface de reserva do Apps Script está inicialmente em português; o catálogo e navegação do GitHub Pages continuam PT/EN/ES. Não há sincronização automática entre `config/equipment.json` e `apps-script/Equipment.gs`: ao alterar o catálogo, atualize ambos e publique nova versão do Apps Script.

A autenticação usa hash SHA-256 iterado com salt individual e segredo `PASSWORD_PEPPER` no servidor. Isso é melhor do que guardar senhas em texto puro, mas **não equivale a um algoritmo dedicado moderno de hash de senha (Argon2id/scrypt)**. Não reutilize senhas institucionais. A sessão é temporária, mantida no cache do Apps Script (até 6 horas) e não é persistida no GitHub. Há bloqueio simples por usuário após tentativas falhas, que não substitui controles completos de segurança. Para operação institucional crítica, faça uma avaliação de segurança e privacidade antes de disponibilizar o sistema amplamente.

**Não execute o workflow antigo `process-bookings.yml`**; ele foi removido do ZIP. Se ainda existir no repositório, exclua-o manualmente. O JSON antigo `data/reservations.json` não é mais fonte de reservas atuais. O painel público não exibe contagem de reservas/usuários para evitar números incorretos.

## Testes

Verifique: login correto/incorreto, acesso desativado, criação de projeto, cadastro de usuário, equipamento não autorizado, reserva de 2+ horas, conflito entre usuários e logout. **Não foi possível executar uma implantação real do Google Apps Script ou um teste integrado com planilha neste ambiente.**
