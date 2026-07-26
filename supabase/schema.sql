-- =====================================================================
-- App Mentoria Tóca De Ouvido  ·  Banco de dados (Supabase / Postgres)
-- =====================================================================
-- Modelo de 3 camadas de privacidade:
--   1) PRIVADO do dono : e-mail, whatsapp, nome completo, e as OBSERVAÇÕES
--                        das músicas/estudos. Ninguém mais vê.
--   2) PÚBLICO da turma : apelido, foto, faixa, contadores, mural, placar,
--                        reações. Todo aluno ativo vê.
--   3) ADMIN (Tóca)    : vê e edita tudo.
--
-- RLS (Row Level Security) LIGADO em todas as tabelas (nega por padrão).
-- O público lê VIEWS que expõem só as colunas seguras; ninguém lê as
-- tabelas cruas dos outros. Rodar este arquivo inteiro no SQL Editor do
-- Supabase (uma vez). O arquivo storage.sql cuida das fotos.
-- =====================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- TABELAS
-- ---------------------------------------------------------------------

-- Perfil de cada aluno (1 por conta de login em auth.users)
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  email           text,                                   -- privado
  apelido         text,                                   -- público
  nome_completo   text,                                   -- privado
  avatar_url      text,                                   -- público
  cidade          text,                                   -- público
  whatsapp        text,                                   -- privado
  role            text not null default 'aluno' check (role in ('aluno','moderador','admin')),
  mentoria_ativa  boolean not null default false,         -- portão: só ativo vê a turma
  status          text not null default 'ativo' check (status in ('ativo','pausado','saiu')),
  musicas_count   integer not null default 0,             -- denormalizado (trigger)
  xp              integer not null default 0,
  faixa           text not null default 'branca',
  grau            integer not null default 0,
  created_at      timestamptz not null default now(),
  last_active_at  timestamptz
);

-- Config das faixas/graus (tabela oficial "Desafio 30 em 1")
create table if not exists public.niveis (
  id           serial primary key,
  faixa        text not null,
  grau         integer not null,
  a_partir_de  integer not null,   -- nº de músicas tiradas
  ordem        integer not null,
  unique (faixa, grau)
);

-- Músicas tiradas de ouvido
create table if not exists public.musicas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  nome        text not null,
  tom         text,
  graus       jsonb not null default '[]'::jsonb,
  observacao  text,                                       -- PRIVADO (só o dono)
  data        date not null default current_date,
  created_at  timestamptz not null default now()
);

-- Estudos com metrônomo (o vídeo mora no Drive; aqui só guardamos a referência)
create table if not exists public.estudos (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  titulo          text,
  segundos        integer not null default 0,
  bpm             integer,
  video_provider  text check (video_provider in ('gdrive','supabase')),
  video_ref       text,          -- file_id do Drive (ou path no Supabase)
  thumb_ref       text,
  observacao      text,          -- PRIVADO (só o dono)
  data            date not null default current_date,
  created_at      timestamptz not null default now()
);

-- Mural (feed). Posts de música/estudo são criados automaticamente por trigger.
create table if not exists public.posts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  tipo         text not null check (tipo in ('musica','estudo','marco_faixa')),
  musica_id    uuid references public.musicas(id) on delete cascade,
  estudo_id    uuid references public.estudos(id) on delete cascade,
  texto        text,
  auto_gerado  boolean not null default true,
  oculto       boolean not null default false,   -- moderação
  fixado       boolean not null default false,   -- moderação
  created_at   timestamptz not null default now()
);

-- Reações de 1 toque (🔥 fogo, ❤ coração, 🎵 nota)
create table if not exists public.reacoes (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  tipo        text not null check (tipo in ('fogo','coracao','nota')),
  created_at  timestamptz not null default now(),
  unique (post_id, user_id, tipo)
);

-- Comentários (o comentário do Tóca = feedback individual à vista da turma)
create table if not exists public.comentarios (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  texto       text not null,
  oculto      boolean not null default false,
  created_at  timestamptz not null default now()
);

-- Códigos da turma (auto-cadastro). Pode ter vários (por lote), com validade/limite.
create table if not exists public.codigos_turma (
  id          uuid primary key default gen_random_uuid(),
  codigo      text unique not null,
  ativo       boolean not null default true,
  validade    date,
  usos_max    integer,
  usos        integer not null default 0,
  created_at  timestamptz not null default now()
);

-- Config global (desafio da semana, mensagens). Só admin edita.
create table if not exists public.app_config (
  id                 integer primary key default 1 check (id = 1),
  desafio_texto      text,
  desafio_meta       integer,
  desafio_progresso  integer default 0,
  mensagens          jsonb default '{}'::jsonb,
  updated_at         timestamptz not null default now()
);
insert into public.app_config (id) values (1) on conflict do nothing;

-- ---------------------------------------------------------------------
-- SEED das faixas (Branca = 0 músicas; começa a subir na Azul)
-- ---------------------------------------------------------------------
insert into public.niveis (faixa, grau, a_partir_de, ordem) values
  ('branca',0,0,0),
  ('azul',1,1,1), ('azul',2,3,2), ('azul',3,5,3),
  ('verde',1,7,4), ('verde',2,9,5),
  ('marrom',1,11,6), ('marrom',2,21,7),
  ('preta',1,31,8), ('preta',2,51,9)
on conflict (faixa, grau) do nothing;

-- ---------------------------------------------------------------------
-- FUNÇÕES DE PAPEL / PORTÃO
-- SECURITY DEFINER: rodam como dono e leem profiles sem disparar RLS
-- (evita recursão infinita nas políticas).
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_mod_or_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','moderador'));
$$;

create or replace function public.is_ativo()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and mentoria_ativa = true);
$$;

-- Faixa/grau a partir do total de músicas
create or replace function public.faixa_para(qtd integer)
returns table(faixa text, grau integer) language sql stable set search_path = public as $$
  select n.faixa, n.grau from public.niveis n
  where n.a_partir_de <= qtd order by n.a_partir_de desc limit 1;
$$;

-- ---------------------------------------------------------------------
-- CADASTRO
-- ---------------------------------------------------------------------
-- Cria o perfil (inativo) assim que a conta de login nasce.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Ativa o aluno com o código da turma (validação no servidor, não dá pra burlar).
create or replace function public.ativar_com_codigo(p_codigo text, p_apelido text)
returns void language plpgsql security definer set search_path = public as $$
declare v_cod public.codigos_turma;
begin
  select * into v_cod from public.codigos_turma
    where codigo = p_codigo and ativo = true for update;
  if not found then raise exception 'Código inválido'; end if;
  if v_cod.validade is not null and v_cod.validade < current_date then
    raise exception 'Código expirado'; end if;
  if v_cod.usos_max is not null and v_cod.usos >= v_cod.usos_max then
    raise exception 'Código esgotado'; end if;

  update public.profiles
     set mentoria_ativa = true,
         apelido = coalesce(p_apelido, apelido),
         status = 'ativo'
   where id = auth.uid();

  update public.codigos_turma set usos = usos + 1 where id = v_cod.id;
end $$;

-- ---------------------------------------------------------------------
-- TRIGGERS DE PROGRESSO / MURAL
-- ---------------------------------------------------------------------
-- Ao registrar música: recalcula contador/faixa, cria o post e, se subiu
-- de faixa/grau, cria o post de marco.
create or replace function public.on_musica_ins()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_of text; v_og integer; v_count integer; v_nf text; v_ng integer;
begin
  select faixa, grau into v_of, v_og from public.profiles where id = new.user_id;
  select count(*) into v_count from public.musicas where user_id = new.user_id;
  select faixa, grau into v_nf, v_ng from public.faixa_para(v_count);
  v_nf := coalesce(v_nf,'branca'); v_ng := coalesce(v_ng,0);

  update public.profiles
     set musicas_count = v_count, faixa = v_nf, grau = v_ng, xp = v_count * 10
   where id = new.user_id;

  insert into public.posts (user_id, tipo, musica_id, texto)
    values (new.user_id, 'musica', new.id, new.nome);

  if (v_nf is distinct from v_of) or (v_ng is distinct from v_og) then
    insert into public.posts (user_id, tipo, texto)
      values (new.user_id, 'marco_faixa', 'Subiu para ' || initcap(v_nf) || ' ' || v_ng || 'º');
  end if;
  return null;
end $$;

drop trigger if exists trg_musica_ins on public.musicas;
create trigger trg_musica_ins after insert on public.musicas
  for each row execute function public.on_musica_ins();

-- Ao apagar música: só recalcula (sem post).
create or replace function public.on_musica_del()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_count integer; v_nf text; v_ng integer;
begin
  select count(*) into v_count from public.musicas where user_id = old.user_id;
  select faixa, grau into v_nf, v_ng from public.faixa_para(v_count);
  update public.profiles
     set musicas_count = v_count, faixa = coalesce(v_nf,'branca'),
         grau = coalesce(v_ng,0), xp = v_count * 10
   where id = old.user_id;
  return null;
end $$;

drop trigger if exists trg_musica_del on public.musicas;
create trigger trg_musica_del after delete on public.musicas
  for each row execute function public.on_musica_del();

-- Ao registrar estudo: cria o post do mural.
create or replace function public.on_estudo_ins()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.posts (user_id, tipo, estudo_id, texto)
    values (new.user_id, 'estudo', new.id, coalesce(new.titulo, 'Estudo'));
  return null;
end $$;

drop trigger if exists trg_estudo_ins on public.estudos;
create trigger trg_estudo_ins after insert on public.estudos
  for each row execute function public.on_estudo_ins();

-- ---------------------------------------------------------------------
-- VIEWS PÚBLICAS  (expõem só o que a turma pode ver; sem e-mail/observação)
-- São views "definer" (dono = postgres) e filtram por is_ativo(): quem não
-- está ativo não enxerga nada.
-- ---------------------------------------------------------------------
create or replace view public.perfis_publicos as
  select id, apelido, avatar_url, cidade, faixa, grau, musicas_count, xp, created_at
  from public.profiles
  where mentoria_ativa = true and (public.is_ativo() or public.is_admin());

create or replace view public.musicas_publicas as
  select m.id, m.user_id, m.nome, m.tom, m.graus, m.data, m.created_at
  from public.musicas m
  join public.profiles p on p.id = m.user_id
  where p.mentoria_ativa = true and (public.is_ativo() or public.is_admin());

create or replace view public.estudos_publicos as
  select e.id, e.user_id, e.titulo, e.segundos, e.bpm,
         e.video_provider, e.video_ref, e.thumb_ref, e.data, e.created_at
  from public.estudos e
  join public.profiles p on p.id = e.user_id
  where p.mentoria_ativa = true and (public.is_ativo() or public.is_admin());

create or replace view public.feed as
  select po.id, po.tipo, po.texto, po.created_at, po.fixado,
         po.musica_id, po.estudo_id,
         pp.id as autor_id, pp.apelido, pp.avatar_url, pp.faixa, pp.grau
  from public.posts po
  join public.perfis_publicos pp on pp.id = po.user_id
  where po.oculto = false
  order by po.fixado desc, po.created_at desc;

-- ---------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------

-- profiles ------------------------------------------------------------
alter table public.profiles enable row level security;
grant select on public.profiles to authenticated;             -- RLS limita as linhas
-- IMPORTANTE: o aluno só recebe permissão NESTAS colunas. Sem permissão em
-- role/mentoria_ativa/musicas_count/faixa/etc., ele não consegue se auto-promover
-- nem se auto-ativar. As mudanças sensíveis passam pelas funções admin_* abaixo.
grant update (apelido, nome_completo, avatar_url, cidade, whatsapp) on public.profiles to authenticated;
create policy prof_sel on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy prof_upd on public.profiles
  for update using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Ações do admin sobre um aluno (rodam como dono; conferem is_admin() por dentro)
create or replace function public.admin_set_ativo(p_user uuid, p_ativo boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Apenas admin'; end if;
  update public.profiles set mentoria_ativa = p_ativo where id = p_user;
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Apenas admin'; end if;
  if p_role not in ('aluno','moderador','admin') then raise exception 'Papel inválido'; end if;
  update public.profiles set role = p_role where id = p_user;
end $$;

create or replace function public.admin_set_status(p_user uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Apenas admin'; end if;
  if p_status not in ('ativo','pausado','saiu') then raise exception 'Status inválido'; end if;
  update public.profiles set status = p_status where id = p_user;
end $$;

-- musicas -------------------------------------------------------------
alter table public.musicas enable row level security;
grant select, insert, update, delete on public.musicas to authenticated;
create policy mus_sel on public.musicas
  for select using (user_id = auth.uid() or public.is_admin());
create policy mus_ins on public.musicas
  for insert with check (user_id = auth.uid() and public.is_ativo());
create policy mus_upd on public.musicas
  for update using (user_id = auth.uid() or public.is_admin());
create policy mus_del on public.musicas
  for delete using (user_id = auth.uid() or public.is_admin());

-- estudos -------------------------------------------------------------
alter table public.estudos enable row level security;
grant select, insert, update, delete on public.estudos to authenticated;
create policy est_sel on public.estudos
  for select using (user_id = auth.uid() or public.is_admin());
create policy est_ins on public.estudos
  for insert with check (user_id = auth.uid() and public.is_ativo());
create policy est_upd on public.estudos
  for update using (user_id = auth.uid() or public.is_admin());
create policy est_del on public.estudos
  for delete using (user_id = auth.uid() or public.is_admin());

-- posts ---------------------------------------------------------------
alter table public.posts enable row level security;
grant select, insert, update, delete on public.posts to authenticated;
create policy post_sel on public.posts
  for select using ((oculto = false and public.is_ativo()) or user_id = auth.uid() or public.is_admin());
create policy post_ins on public.posts
  for insert with check (user_id = auth.uid() and public.is_ativo());
create policy post_upd on public.posts
  for update using (public.is_mod_or_admin()) with check (public.is_mod_or_admin());
create policy post_del on public.posts
  for delete using (user_id = auth.uid() or public.is_admin());

-- reacoes -------------------------------------------------------------
alter table public.reacoes enable row level security;
grant select, insert, delete on public.reacoes to authenticated;
create policy rea_sel on public.reacoes
  for select using (public.is_ativo() or public.is_admin());
create policy rea_ins on public.reacoes
  for insert with check (user_id = auth.uid() and public.is_ativo());
create policy rea_del on public.reacoes
  for delete using (user_id = auth.uid() or public.is_admin());

-- comentarios ---------------------------------------------------------
alter table public.comentarios enable row level security;
grant select, insert, update, delete on public.comentarios to authenticated;
create policy com_sel on public.comentarios
  for select using ((oculto = false and public.is_ativo()) or user_id = auth.uid() or public.is_admin());
create policy com_ins on public.comentarios
  for insert with check (user_id = auth.uid() and public.is_ativo());
create policy com_upd on public.comentarios
  for update using (public.is_mod_or_admin()) with check (public.is_mod_or_admin());
create policy com_del on public.comentarios
  for delete using (user_id = auth.uid() or public.is_admin());

-- niveis (config pública, só admin muda) ------------------------------
alter table public.niveis enable row level security;
grant select on public.niveis to anon, authenticated;
grant insert, update, delete on public.niveis to authenticated;
create policy niv_sel on public.niveis for select using (true);
create policy niv_admin on public.niveis for all
  using (public.is_admin()) with check (public.is_admin());

-- codigos_turma (só admin; aluno usa a função ativar_com_codigo) ------
alter table public.codigos_turma enable row level security;
grant select, insert, update, delete on public.codigos_turma to authenticated;
create policy cod_admin on public.codigos_turma for all
  using (public.is_admin()) with check (public.is_admin());

-- app_config (leitura pública do desafio; só admin edita) -------------
alter table public.app_config enable row level security;
grant select on public.app_config to anon, authenticated;
grant update on public.app_config to authenticated;
create policy cfg_sel on public.app_config for select using (true);
create policy cfg_upd on public.app_config for update
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- PERMISSÃO DE EXECUÇÃO DAS FUNÇÕES
-- ---------------------------------------------------------------------
grant execute on function public.is_admin()         to anon, authenticated;
grant execute on function public.is_mod_or_admin()  to anon, authenticated;
grant execute on function public.is_ativo()         to anon, authenticated;
grant execute on function public.faixa_para(integer) to anon, authenticated;
grant execute on function public.ativar_com_codigo(text, text) to authenticated;
grant execute on function public.admin_set_ativo(uuid, boolean) to authenticated;
grant execute on function public.admin_set_role(uuid, text)     to authenticated;
grant execute on function public.admin_set_status(uuid, text)   to authenticated;

-- Views: leitura para quem está logado (o filtro is_ativo() já protege)
grant select on public.perfis_publicos, public.musicas_publicas,
                public.estudos_publicos, public.feed to authenticated;

-- Fim do schema. Rode storage.sql em seguida para as fotos de perfil.
