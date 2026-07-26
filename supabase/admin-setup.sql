-- =====================================================================
-- Configuração inicial do admin (Tóca) e do código da turma.
-- Rodar no SQL Editor DEPOIS de você criar a SUA conta de login no app
-- (ou pelo painel Authentication > Add user), com o e-mail que você usar.
-- =====================================================================

-- 1) Te transformar em ADMIN (troque o e-mail pelo que você usou)
update public.profiles
   set role = 'admin', mentoria_ativa = true, apelido = 'Toca'
 where id = (select id from auth.users where email = 'SEU-EMAIL-AQUI@exemplo.com');

-- 2) Criar o código da turma (aqui: 100 usos, sem validade). Troque à vontade.
insert into public.codigos_turma (codigo, usos_max)
values ('TOCA-2026', 100)
on conflict (codigo) do nothing;

-- 3) (opcional) Definir o desafio da semana que aparece no topo do mural
update public.app_config
   set desafio_texto = 'Tirar 60 músicas de ouvido essa semana',
       desafio_meta = 60, desafio_progresso = 0
 where id = 1;

-- Conferir se deu certo:
-- select apelido, role, mentoria_ativa from public.profiles where role = 'admin';
-- select codigo, usos, usos_max from public.codigos_turma;
