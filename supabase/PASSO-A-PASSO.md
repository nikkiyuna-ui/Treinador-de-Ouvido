# Passo a passo, deixar o App Tóca De Ouvido funcional

Guia pra Nikki. A parte técnica pesada (o banco e a segurança) já está pronta e
testada nos arquivos desta pasta. Aqui é só o que **você** faz uma vez.

## O que já está pronto (feito e testado)
- `schema.sql`, o banco de dados inteiro (perfis, músicas, estudos, mural, reações)
  com as **3 camadas de segurança** (privado do aluno, público da turma, admin).
- `storage.sql`, as regras das fotos de perfil.
- `admin-setup.sql`, te vira admin e cria o código da turma.
- `test/`, os testes de segurança que eu rodei (12 testes, todos passaram).

## PARTE 1, você faz (uns 15 minutos)

1. **Criar a conta**: entre em https://supabase.com e crie uma conta grátis
   (pode entrar com o Google).
2. **Criar o projeto**: clique em *New project*. Dê um nome (ex: `tocadeouvido`),
   escolha a região **South America (São Paulo)**, e crie uma **senha do banco**
   (guarde essa senha num lugar seguro).
3. **Rodar o banco**: no menu lateral, abra **SQL Editor** > *New query*. Cole
   TODO o conteúdo de `schema.sql`, clique em **Run**. Depois faça o mesmo com
   `storage.sql`. (Se aparecer "Success", deu certo.)
4. **Criar a sua conta de login**: no menu **Authentication** > *Add user* >
   crie um usuário com o **seu e-mail e uma senha**. (Vai ser a sua conta de Tóca.)
5. **Virar admin**: volte no **SQL Editor**, cole o `admin-setup.sql`, troque o
   `SEU-EMAIL-AQUI` pelo e-mail do passo 4, e clique em **Run**.
6. **Me mandar 2 coisas** (pode colar aqui na conversa, são públicas):
   - Em **Project Settings > API**: a **Project URL** e a chave **anon public**.
   - **NUNCA** me mande a chave `service_role` nem a senha do banco. Essas são só
     suas.

## PARTE 2, eu faço (assim que você me mandar a URL e a anon key)
- Ligo o **login/cadastro** de verdade no app (e-mail + senha + código da turma).
- Ligo cada tela pra **salvar e ler da nuvem**: registrar música/estudo salva
  mesmo, placar e mural ao vivo, foto de perfil real.
- Faço o **painel do Tóca** (admin): ver tudo, moderar o mural, gerar código,
  ativar/desativar aluno.
- Depois a gente pluga o **Google Drive** pros vídeos (precisa de uma autorização
  sua no Google, eu te guio quando chegar a hora).
- Antes de abrir pros alunos, a gente **testa junto** e eu reviso a segurança.

## Verdades pra você lembrar
- **Grátis pra testar.** Quando abrir pros alunos de verdade, o plano pago
  (~US$25/mês) evita o projeto pausar sozinho e garante backup.
- **"Esqueci a senha"** automático precisa de um serviço de e-mail extra (depois).
  No começo, você reseta a senha de quem esquecer, pelo painel.
- **Código da turma** pode vazar. Por isso ele tem limite de usos e você pode
  desativar quem entrou sem ser aluno. A lista de quem entrou fica visível pra você.
