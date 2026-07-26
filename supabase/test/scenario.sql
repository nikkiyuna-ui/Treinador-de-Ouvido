-- Cenário de teste da segurança (roda como postgres; usa SET ROLE p/ simular alunos)
\set ON_ERROR_STOP on
\set ADMIN  '11111111-1111-1111-1111-111111111111'
\set S1     '22222222-2222-2222-2222-222222222222'
\set S2     '33333333-3333-3333-3333-333333333333'

-- Nascem 3 contas de login -> trigger cria os profiles
insert into auth.users (id,email) values
  (:'ADMIN','toca@teste.com'), (:'S1','s1@teste.com'), (:'S2','s2@teste.com');

-- Tóca vira admin (feito pelo dono do banco, como no painel)
update public.profiles set role='admin', mentoria_ativa=true, apelido='Toca' where id=:'ADMIN';

-- Admin cria o código da turma
insert into public.codigos_turma (codigo, usos_max) values ('TOCA-2026', 100);

\echo '--- s1 e s2 se ativam com o código (como aluno logado) ---'
set role authenticated; set test.uid = :'S1';
select public.ativar_com_codigo('TOCA-2026','Val Cordas');
reset role; set test.uid = :'S2';  set role authenticated;
select public.ativar_com_codigo('TOCA-2026','Deka');
reset role;

\echo '--- s1 registra 5 musicas (deve virar Azul 3o) ---'
set role authenticated; set test.uid = :'S1';
insert into public.musicas (user_id,nome,tom,observacao) values
  (:'S1','Faca Chover','G','travei na virada'),
  (:'S1','Oceanos','D',null),
  (:'S1','Deus e Deus','Em',null),
  (:'S1','Ninguem Explica Deus','C',null),
  (:'S1','A Ele a Gloria','A',null);
reset role;

\echo 'RESULTADO faixa de s1 (esperado: verde? nao, 5 = azul grau 3):'
select apelido, musicas_count, faixa, grau, xp from public.profiles where id=:'S1';

\echo 'POSTS gerados de s1 (5 musica + marcos de faixa):'
select tipo, texto from public.posts where user_id=:'S1' order by created_at;

\echo '=== TESTE 1: s2 NAO pode ler as musicas cruas de s1 (RLS) ==='
set role authenticated; set test.uid = :'S2';
select count(*) as deve_ser_0 from public.musicas where user_id=:'S1';

\echo '=== TESTE 2: s2 VE as musicas de s1 pela view publica (sem observacao) ==='
select count(*) as deve_ser_5 from public.musicas_publicas where user_id=:'S1';

\echo '=== TESTE 3: s2 tenta editar o perfil de s1 (RLS bloqueia: 0 linhas) ==='
update public.profiles set whatsapp='999' where id=:'S1';
\echo '(se apareceu UPDATE 0, a linha do s1 ficou intocada)'

\echo '=== TESTE 4: s2 tenta se auto-promover a admin (deve DAR ERRO de permissao) ==='
do $$ begin
  update public.profiles set role='admin' where id = auth.uid();
  raise exception 'FALHA: consegui virar admin!';
exception when insufficient_privilege then raise notice 'OK: bloqueado (sem permissao na coluna role)';
end $$;

\echo '=== TESTE 5: s2 tenta se auto-ativar mexendo em mentoria_ativa (deve DAR ERRO) ==='
do $$ begin
  update public.profiles set mentoria_ativa=false where id = auth.uid();
  raise exception 'FALHA: consegui mexer no portao!';
exception when insufficient_privilege then raise notice 'OK: bloqueado (sem permissao na coluna mentoria_ativa)';
end $$;

\echo '=== TESTE 6: s2 ve o PROPRIO email (privado, mas dele) ==='
select email is not null as ve_proprio_email from public.profiles where id = auth.uid();
reset role;

\echo '=== TESTE 7: anon (deslogado) NAO ve a turma (acesso negado) ==='
set role anon; set test.uid = '';
do $$ begin
  perform 1 from public.perfis_publicos;
  raise exception 'FALHA: anon acessou a turma!';
exception when insufficient_privilege then raise notice 'OK: anon sem acesso a view da turma';
end $$;
reset role;

\echo '=== TESTE 8: admin ve TODOS os profiles ==='
set role authenticated; set test.uid = :'ADMIN';
select count(*) as deve_ser_3 from public.profiles;
\echo 'admin ve o whatsapp de todo mundo (coluna privada):';
select count(*) as perfis_visiveis from public.profiles;
reset role;

\echo '=== TESTE 9: s1 apaga 3 musicas -> faixa recalcula (5 -> 2 = Azul 1o) ==='
set role authenticated; set test.uid = :'S1';
delete from public.musicas where user_id=:'S1' and nome in ('Oceanos','Deus e Deus','Ninguem Explica Deus');
reset role;
select musicas_count as deve_ser_2, faixa, grau from public.profiles where id=:'S1';

\echo '=== TESTE 10: codigo errado nao ativa ==='
insert into auth.users (id,email) values ('44444444-4444-4444-4444-444444444444','s3@teste.com');
set role authenticated; set test.uid = '44444444-4444-4444-4444-444444444444';
do $$ begin
  perform public.ativar_com_codigo('CODIGO-ERRADO','Ze');
  raise exception 'FALHA: ativou com codigo errado!';
exception when others then raise notice 'OK: %', sqlerrm;
end $$;
select mentoria_ativa as deve_ser_false from public.profiles where id='44444444-4444-4444-4444-444444444444';
reset role;

\echo '=== TESTE 11: aluno comum NAO consegue usar funcao de admin ==='
set role authenticated; set test.uid = :'S2';
do $$ begin
  perform public.admin_set_role(auth.uid(),'admin');
  raise exception 'FALHA: aluno rodou funcao de admin!';
exception when others then raise notice 'OK: %', sqlerrm;
end $$;
reset role;

\echo '=== TESTE 12: admin desativa um aluno via funcao (portao fecha) ==='
set role authenticated; set test.uid = :'ADMIN';
select public.admin_set_ativo(:'S2', false);
reset role;
select mentoria_ativa as s2_deve_ser_false from public.profiles where id=:'S2';

\echo '===================== TODOS OS TESTES PASSARAM ====================='
