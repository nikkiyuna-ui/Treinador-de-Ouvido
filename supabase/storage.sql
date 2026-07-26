-- =====================================================================
-- Fotos de perfil (Storage do Supabase)
-- Rodar no SQL Editor DEPOIS do schema.sql.
-- =====================================================================

-- Balde (bucket) das fotos de perfil. Público para leitura (foto não é segredo).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Cada aluno só mexe na PRÓPRIA pasta: avatars/<id-do-aluno>/foto.jpg
create policy "avatars leitura publica" on storage.objects
  for select using ( bucket_id = 'avatars' );

create policy "avatars upload do dono" on storage.objects
  for insert to authenticated
  with check ( bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text );

create policy "avatars troca do dono" on storage.objects
  for update to authenticated
  using ( bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text );

create policy "avatars apagar do dono" on storage.objects
  for delete to authenticated
  using ( bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text );
