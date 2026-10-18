# LabScheduler — versão inicial independente (v0.1)

Aplicação React/TypeScript para agendamento científico, com hospedagem do frontend em GitHub Pages e backend Supabase/PostgreSQL. **Não depende do Lovable.**

## Estado real desta entrega

**Implementado:** interface responsiva; autenticação passwordless por e-mail; leitura de equipamentos/projetos autorizados; criação de reserva; bloqueio de conflitos concorrentes por restrição PostgreSQL; check-in/check-out/cancelamento via RPC; solicitação e aprovação de mudança de fonte de custeio com proibição de autoaprovação; histórico de decisões; exportação CSV e impressão em PDF pelo navegador; workflow de deploy GitHub Pages; RLS de acesso inicial.

**Não implementado nesta versão:** calendário visual completo, recorrência, QR code, Google OAuth, treinamento de operador, notificações, criação administrativa de instituições/equipamentos/projetos pela UI, cadastro de clientes, orçamento PDF, ordens de serviço, FUJB, notas fiscais, conciliação financeira, relatórios XLSX completos, backup automatizado e testes automatizados. A tela de orçamentos indica explicitamente a indisponibilidade. Não usar em produção sem auditoria de segurança, testes de concorrência e revisão das políticas institucionais.

## Publicar no GitHub Pages

1. Crie repositório GitHub, por exemplo `LabScheduler`.
2. Extraia o ZIP e envie **o conteúdo da pasta `LabScheduler` para a raiz do repositório** (o `package.json` deve ficar na raiz).
3. Crie um projeto Supabase (plano gratuito, sujeito a limites).
4. No SQL Editor do Supabase, execute `supabase/migrations/001_init.sql`.
5. Em GitHub → Settings → Secrets and variables → Actions → **Variables**, configure `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` (a chave pública/publishable, nunca service_role).
6. No Supabase → Authentication → URL Configuration, cadastre `https://SEU_USUARIO.github.io/LabScheduler/` como Redirect URL e, se apropriado, Site URL. Se o nome do repositório for diferente, use esse nome no caminho.
7. No GitHub → Settings → Pages, escolha **GitHub Actions** como Source. Faça push para `main` e acompanhe a Action de deploy.
8. O site abrirá em `https://SEU_USUARIO.github.io/LabScheduler/`.

## Desenvolvimento local

```bash
npm install
cp .env.example .env
# preencha VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY
# para desenvolvimento local, defina VITE_BASE_PATH=/
npm run dev
npm run build
```

Sem variáveis Supabase, a interface abre em **DEMO** com instrumentos e projetos fictícios. Nesse modo não salva reservas e não finge persistência.

## Inicialização administrativa

O primeiro administrador precisa ser cadastrado **manualmente** por um operador confiável no SQL Editor, após autenticar uma vez para criar seu `auth.users.id`:

```sql
-- Substitua por dados reais; execute no SQL Editor como administrador do banco.
insert into public.institutions(name) values ('IPPN / UFRJ') returning id;
insert into public.memberships(institution_id,user_id,role)
values ('UUID_DA_INSTITUICAO','UUID_DO_USUARIO','admin');
insert into public.equipment(institution_id,name,lab,active)
values ('UUID_DA_INSTITUICAO','LC–HRMS/MS','LabCROM',true);
insert into public.projects(institution_id,name,scientific_lead,financial_lead,funding_source)
values ('UUID_DA_INSTITUICAO','Projeto inicial','Nome do coordenador','Nome do responsável financeiro','Fonte inicial') returning id;
insert into public.project_members(project_id,user_id)
values ('UUID_DO_PROJETO','UUID_DO_USUARIO');
```

## Observações de segurança

- RLS e funções PostgreSQL fazem a verificação de autorização no servidor.
- Reservas de uma mesma instituição são visíveis a membros dessa instituição. Revise visibilidade e LGPD antes de incluir informações sensíveis em `purpose`.
- O administrador da base precisa administrar vínculos e permissões até que seja implementada a interface administrativa.
- O schema inicial exige revisão de segurança antes de uso real; funções SECURITY DEFINER merecem auditoria.
- Não há emissão fiscal nem armazenamento de XML/PDF nesta versão.
- GitHub Pages hospeda apenas a interface; a persistência depende do Supabase.

## Idiomas / Languages / Idiomas

A interface suporta **Português (PT-BR)**, **English (EN)** e **Español (ES)**, com seletor `PT | EN | ES` no cabeçalho e na tela de login. A preferência é salva no `localStorage` do navegador e, na primeira visita, o idioma é inferido da configuração do navegador (outros idiomas usam português). Datas seguem a localidade selecionada. Dados fornecidos pelos usuários, como nomes de projetos e observações, **não são traduzidos automaticamente**.

The UI supports Portuguese, English and Spanish. Language selection persists locally. User-entered data is not automatically translated.


## v0.3 — Catálogo administrado pelo GitHub

O arquivo **`config/equipment.json`** contém 27 itens: 25 agendáveis (24 instrumentos originais + 1 concentrador de N₂) e 2 geradores Peak NM32LA acessórios. O concentrador está associado provisoriamente ao gerador `CodWR481V/24`; confirme fisicamente qual gerador o atende antes de uso real. Fabricante e modelo do concentrador estão como não informados.

### Ativar/desativar e publicar informes

1. No GitHub, abra `config/equipment.json` e clique em **Edit** (ícone lápis).
2. Localize o equipamento por `code` (código PNIPE ou `LOCAL-N2-CONCENTRATOR`).
3. Altere `"bookable": true` para `false` para impedir **novas** reservas, ou vice-versa. Altere `"operational_status"` para `"maintenance"` para indicar manutenção. Acessórios permanecem `bookable:false`.
4. Preencha `notice.pt`, `notice.en` e `notice.es` para avisos exibidos na ficha e na reserva; texto vazio remove o aviso.
5. Faça **Commit changes** em `main`. O GitHub Actions publica a interface. Com o workflow de sincronização configurado, também atualiza o banco Supabase.

**Para controle efetivo de reservas no servidor**, execute `supabase/migrations/002_equipment_catalog.sql` no SQL Editor e configure os três GitHub **Actions Secrets**: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` e `LABSCHEDULER_INSTITUTION_ID` (UUID da instituição cadastrada). A chave `service_role` deve existir **somente em Secrets**, jamais em arquivos, variáveis `VITE_` ou no frontend. A sincronização não funciona sem estes Secrets. O workflow `Sync equipment catalog to Supabase` usa a chave privilegiada exclusivamente durante o GitHub Actions; proteja a branch `main` com revisão obrigatória e restrinja acesso ao repositório.

O `code` é usado como chave estável; a sincronização faz upsert e **não apaga** instrumentos nem reservas antigas. Desativar um equipamento bloqueia novas reservas; reservas existentes permanecem no histórico e exigem gestão/cancelamento manual. A indisponibilidade do gerador associado bloqueia novas reservas do concentrador quando o catálogo estiver sincronizado.

Sem Supabase, o site apresenta o catálogo e os informes no modo demonstração, mas não salva reservas. Se o banco já contém instrumentos antigos sem `code`, estes não são automaticamente vinculados ao catálogo e devem ser reconciliados pelo administrador antes da operação.


## Tela branca no GitHub Pages — correção v0.3.1

1. Envie **o conteúdo da pasta `LabScheduler/`**, não a pasta como subdiretório, para a raiz do repositório.
2. Em **Settings → Pages → Build and deployment → Source**, escolha **GitHub Actions** (não `Deploy from a branch`).
3. Confirme que o arquivo `.github/workflows/deploy.yml` foi enviado (incluindo a pasta oculta `.github`).
4. Na aba **Actions**, execute `Deploy GitHub Pages` usando `Run workflow` e aguarde o status verde.
5. Abra a URL exibida no job `deploy`. O endereço de projeto é `https://USUARIO.github.io/NOME-DO-REPOSITORIO/`.
6. Se continuar em branco, abra F12 → Console e copie o erro. Erros 404 em `/assets/...` indicam base path ou publicação incorreta.

O workflow desta versão remove a opção de cache do npm, que exige um `package-lock.json` inexistente no pacote anterior. A entrada do Vite também foi ajustada para caminho relativo.

**Nota:** o Supabase não é necessário para visualizar a interface demonstrativa. Sem as variáveis de ambiente, reservas não são persistidas.
