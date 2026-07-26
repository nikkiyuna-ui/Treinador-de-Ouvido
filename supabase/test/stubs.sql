-- Stubs para TESTAR o schema fora do Supabase (NÃO rodar no Supabase).
-- Recria o mínimo do ambiente Supabase: schema auth, auth.users, auth.uid()
-- e os papéis anon/authenticated/service_role.
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);

-- No Supabase auth.uid() lê o JWT. No teste, lê uma variável de sessão.
create or replace function auth.uid() returns uuid
language sql stable as $$ select nullif(current_setting('test.uid', true),'')::uuid $$;

do $$ begin create role anon nologin;          exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin;  exception when duplicate_object then null; end $$;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
