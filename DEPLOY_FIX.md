# Correção da tela branca no GitHub Pages

O repositório publicado não contém `.github/workflows/deploy.yml`, então o GitHub Pages está servindo `index.html` com referência direta a `src/main.tsx` em vez de compilar a aplicação.

1. Faça upload de **todos os arquivos, incluindo a pasta oculta `.github`**, para a raiz do repositório.
2. Confirme que `.github/workflows/deploy.yml` existe no GitHub.
3. Em Settings > Pages > Build and deployment > Source, selecione **GitHub Actions**.
4. Na aba Actions, execute **Deploy GitHub Pages** e verifique que Install dependencies, Build, Verify compiled output e Deploy passaram.
5. Acesse https://ippn-ufrj.github.io/LabScheduler/ e atualize com Ctrl+Shift+R.

Se o upload pelo navegador não mostrar `.github`, crie a pasta e o arquivo diretamente no GitHub ou use Git. A ausência de configuração do Supabase deve ativar o modo de demonstração, não causar tela branca.
