# LabScheduler v0.5 — GitHub-only

Site: https://ippn-ufrj.github.io/LabScheduler/

## O que funciona

- GitHub Pages para site React/Vite, PT/EN/ES, 27 equipamentos, avisos por equipamento e calendário semanal.
- Ocupação pública lida de `data/reservations.json`.
- Solicitação de reserva abre uma **GitHub Issue** preenchida. O solicitante **precisa ter uma conta GitHub** e autenticar-se no GitHub.
- GitHub Actions valida a identidade real do autor da Issue, autorização em `config/users.json`, projeto ativo e autorizado, equipamento agendável, datas e conflito de horários; então grava reserva pública sanitizada e comenta o resultado.
- Nenhuma senha, token ou credencial administrativa é enviada ao navegador.

## Limitações IMPORTANTES

- **Não há formulário de login com senha própria.** O login é o do GitHub. Não é possível implementar login próprio seguro exclusivamente com GitHub Pages + JSON público.
- **GitHub Issues do repositório público são públicas.** NÃO registre amostras, finalidade científica, informações pessoais, financeiras ou dados sensíveis nas solicitações. O formulário transmite somente código do equipamento, código de projeto e intervalo.
- O `users.json` público contém **apenas identificadores GitHub e permissões**; nunca e-mails privados, senhas ou hashes.
- Reservas são **assíncronas** e dependem da execução do Actions. O calendário pode demorar alguns minutos a atualizar. Não existe confirmação imediata.
- Esta versão **não implementa** check-in/check-out autenticados, faturamento, aprovações financeiras, relatórios com dados privados, cancelamento pelo usuário, manutenção transacional sofisticada ou login por senha independente.
- A simultaneidade é serializada pelo grupo `booking-state` no GitHub Actions; falhas temporárias no `git push` ainda podem exigir intervenção administrativa. A atualização do calendário depende do deploy.
- Um administrador do repositório com permissão de escrita pode alterar os JSON. Não conceda escrita a pesquisadores sem necessidade.

## Instalação

1. Copie **todo o conteúdo deste pacote** para a raiz do repositório `IPPN-UFRJ/LabScheduler`, substituindo a versão antiga. A pasta `.github` deve ser incluída.
2. GitHub → Settings → Pages → Source: **GitHub Actions**.
3. GitHub → Settings → General → Features: habilite **Issues**.
4. GitHub → Settings → Actions → General → Workflow permissions: selecione **Read and write permissions** (necessário para `process-bookings.yml` gravar `data/reservations.json` e comentar Issues). Se não for possível, revise permissões da organização.
5. Edite `config/users.json`: substitua `REPLACE_WITH_YOUR_GITHUB_USERNAME` pelo seu nome de usuário GitHub, altere `active` para `true`. Adicione usuários com identificador GitHub e autorizações explícitas por instrumento e projeto.
6. Edite `config/projects.json`: cadastre projetos com `id` estável e `active:true`; autorize seus IDs em `users.json`.
7. Configure equipamentos e avisos em `config/equipment.json` (`bookable`, `operational_status`, `notice.pt/en/es`). Geradores de nitrogênio são acessórios não agendáveis.
8. Faça commit. O workflow `Deploy LabScheduler` publica o site. O workflow `Process booking requests` processa Issues.
9. Faça um teste com sua conta GitHub autorizada: selecione equipamento, projeto e horário, clique em **Solicitar reserva via GitHub**; confira a Issue e o resultado do workflow. Uma reserva aceita aparece em `data/reservations.json`.

## Segurança e privacidade

- GitHub Pages não é um backend autenticado. **Nunca coloque senhas, hashes, tokens de acesso, service role keys ou dados confidenciais em `config/` ou `data/`.**
- A verificação de autorização ocorre no Actions, usando o login fornecido pela API do GitHub para a Issue, nunca uma identidade declarada no navegador.
- A disponibilidade pública contém apenas ID da reserva, equipamento, intervalo e status.
- Se o repositório tiver regras de proteção de branch, o `github-actions[bot]` poderá não conseguir fazer push. Configure a política institucional adequadamente, sem desabilitar proteções indiscriminadamente.
- Não execute código fornecido no corpo de Issues. O processador usa somente JSON e valida os campos.

## Desenvolvimento

```bash
npm install
npm run dev
npm run build
```

## Estrutura

- `src/` interface React.
- `config/equipment.json` instrumentos e avisos.
- `config/users.json` contas GitHub autorizadas (sem senhas).
- `config/projects.json` projetos elegíveis.
- `data/reservations.json` disponibilidade pública.
- `.github/workflows/deploy.yml` publicação.
- `.github/workflows/process-bookings.yml` validação e registro.
- `scripts/process_booking.py` verificador de autorização/conflitos.
