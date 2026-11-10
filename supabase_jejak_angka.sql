-- JEJAK ANGKA: skema Supabase untuk repository LKPD per jurusan
-- Jalankan di Supabase Dashboard > SQL Editor.
-- Bucket Storage dibuat melalui Storage > New bucket dengan nama: lkpd
-- Pilih Public bucket agar siswa dapat mengunduh file tanpa login.
-- Atur bucket file size limit ke 10 MB dan allowed MIME:
-- application/pdf, application/msword,
-- application/vnd.openxmlformats-officedocument.wordprocessingml.document

create extension if not exists pgcrypto;

-- Profil pengguna. Akun dibuat melalui Supabase Auth.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'siswa'
    check (role in ('admin', 'guru', 'siswa')),
  department text
    check (department is null or department in ('TKRO', 'AKL', 'TJKT', 'DKV', 'TITL', 'MPLB')),
  created_at timestamptz not null default now()
);

-- Metadata LKPD. File aslinya disimpan di Supabase Storage, bukan di database.
create table if not exists public.lkpd (
  id uuid primary key default gen_random_uuid(),
  department text not null
    check (department in ('TKRO', 'AKL', 'TJKT', 'DKV', 'TITL', 'MPLB')),
  title text not null,
  class_name text not null default '',
  description text not null default '',
  file_name text not null,
  storage_path text not null unique,
  file_size bigint not null check (file_size > 0 and file_size <= 10485760),
  mime_type text not null
    check (mime_type in (
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    )),
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists lkpd_department_created_idx
  on public.lkpd (department, created_at desc);

alter table public.profiles enable row level security;
alter table public.lkpd enable row level security;

-- Pengguna dapat membaca profil sendiri. Role tidak boleh diubah sendiri.
drop policy if exists "profiles_read_own" on public.profiles;
create policy "profiles_read_own"
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()));

-- Repository LKPD dapat dibaca publik (termasuk siswa yang belum login).
drop policy if exists "lkpd_read_all" on public.lkpd;
create policy "lkpd_read_all"
  on public.lkpd for select
  to anon, authenticated
  using (true);

-- Hanya Admin dan Guru yang dapat menambahkan metadata LKPD.
drop policy if exists "lkpd_insert_manager" on public.lkpd;
create policy "lkpd_insert_manager"
  on public.lkpd for insert
  to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role in ('admin', 'guru')
        and (p.role = 'admin' or p.department is null or p.department = department)
    )
  );

-- Hanya Admin dan Guru yang dapat menghapus metadata LKPD.
drop policy if exists "lkpd_delete_manager" on public.lkpd;
create policy "lkpd_delete_manager"
  on public.lkpd for delete
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role in ('admin', 'guru')
        and (p.role = 'admin' or p.department is null or p.department = department)
    )
  );

-- Storage policies untuk bucket "lkpd".
-- Bucket public hanya membuat file dapat dibaca/diunduh publik;
-- upload dan delete tetap dibatasi oleh kebijakan berikut.
drop policy if exists "lkpd_storage_upload_manager" on storage.objects;
create policy "lkpd_storage_upload_manager"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'lkpd'
    and (storage.foldername(name))[1] in ('TKRO', 'AKL', 'TJKT', 'DKV', 'TITL', 'MPLB')
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role in ('admin', 'guru')
        and (
          p.role = 'admin'
          or p.department is null
          or p.department = (storage.foldername(name))[1]
        )
    )
  );

drop policy if exists "lkpd_storage_delete_manager" on storage.objects;
create policy "lkpd_storage_delete_manager"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'lkpd'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role in ('admin', 'guru')
        and (
          p.role = 'admin'
          or p.department is null
          or p.department = (storage.foldername(name))[1]
        )
    )
  );

-- PENTING:
-- 1. Buat bucket "lkpd" di Storage, set Public, file limit 10 MB,
--    allowed MIME types PDF/DOC/DOCX.
-- 2. Setelah membuat akun melalui Authentication, isi role pengguna
--    melalui SQL Editor. Contoh:
--    update public.profiles set role='admin', department=null
--    where id='UUID_USER_DARI_AUTH_USERS';
-- 3. Buat trigger/proses server-side untuk membuat baris profiles saat
--    pengguna baru mendaftar. Jangan izinkan pengguna mengubah role sendiri.
-- 4. Front-end harus memakai Supabase Auth + anon/publishable key.
--    Jangan pernah memasukkan service_role key ke index.html.
