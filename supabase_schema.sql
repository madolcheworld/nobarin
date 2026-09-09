-- ==============================================================================
-- SKEMA DATABASE WATCH PARTY (SUPABASE POSTGRESQL)
-- Jalankan skrip ini di SQL Editor pada Supabase Dashboard Anda
-- ==============================================================================

-- 1. Enable extension pgcrypto untuk gen_random_uuid() jika belum aktif
create extension if not exists "pgcrypto";

-- 2. TABEL: PROFILES
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  username text not null,
  avatar_url text,
  is_guest boolean default false,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 3. TABEL: ROOMS
create table if not exists public.rooms (
  id uuid default gen_random_uuid() primary key,
  code varchar(8) unique not null,
  title text not null,
  description text,
  host_id uuid references public.profiles(id) on delete set null,
  host_name text,
  is_public boolean default true,
  control_mode text check (control_mode in ('host_only', 'collaborative')) default 'host_only',
  current_media_type text check (current_media_type in ('youtube', 'direct_url', null)),
  current_media_url text,
  current_state text default 'paused',
  current_position float default 0,
  livekit_room_name text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()),
  updated_at timestamp with time zone default timezone('utc'::text, now())
);

-- 4. TABEL: ROOM PARTICIPANTS
create table if not exists public.room_participants (
  id uuid default gen_random_uuid() primary key,
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text check (role in ('host', 'co_host', 'viewer')) default 'viewer',
  is_muted boolean default false,
  joined_at timestamp with time zone default timezone('utc'::text, now()),
  unique(room_id, user_id)
);

-- 5. TABEL: ROOM MESSAGES (CHAT)
create table if not exists public.room_messages (
  id uuid default gen_random_uuid() primary key,
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  content text not null,
  type text check (type in ('text', 'system', 'emoji_reaction')) default 'text',
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 6. INDEKS UNTUK OPTIMASI PERFORMA QUERY
create index if not exists idx_rooms_code on public.rooms(code);
create index if not exists idx_rooms_is_public on public.rooms(is_public);
create index if not exists idx_room_messages_room_id on public.room_messages(room_id, created_at desc);
create index if not exists idx_room_participants_room_id on public.room_participants(room_id);

-- 7. ROW LEVEL SECURITY (RLS) POLICIES
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_participants enable row level security;
alter table public.room_messages enable row level security;

-- Kebijakan Profiles
create policy "Profil dapat dibaca oleh siapa saja" 
  on public.profiles for select using (true);

create policy "Pengguna dapat membuat atau memperbarui profil mereka sendiri" 
  on public.profiles for all using (auth.uid() = id);

-- Kebijakan Rooms
create policy "Room dapat dibaca oleh semua pengguna" 
  on public.rooms for select using (true);

create policy "Semua pengguna terotentikasi dapat membuat room" 
  on public.rooms for insert with check (auth.role() in ('authenticated', 'anon'));

create policy "Host atau peserta dapat mengupdate state room" 
  on public.rooms for update using (auth.role() in ('authenticated', 'anon'));

create policy "Semua pengguna dapat menghapus room" 
  on public.rooms for delete using (auth.role() in ('authenticated', 'anon'));

-- Kebijakan Participants
create policy "Peserta room dapat dibaca oleh siapa saja" 
  on public.room_participants for select using (true);

create policy "Pengguna dapat bergabung ke room" 
  on public.room_participants for insert with check (auth.role() in ('authenticated', 'anon'));

create policy "Pengguna dapat keluar atau update status mute mereka" 
  on public.room_participants for all using (auth.role() in ('authenticated', 'anon'));

create policy "Semua pengguna dapat menghapus peserta room" 
  on public.room_participants for delete using (auth.role() in ('authenticated', 'anon'));

-- Kebijakan Chat Messages
create policy "Pesan chat dapat dibaca oleh siapa saja di room" 
  on public.room_messages for select using (true);

create policy "Pengguna dapat mengirim pesan ke room" 
  on public.room_messages for insert with check (auth.role() in ('authenticated', 'anon'));

create policy "Semua pengguna dapat menghapus pesan room" 
  on public.room_messages for delete using (auth.role() in ('authenticated', 'anon'));

-- ==============================================================================
-- 6B. TABEL: ROOM QUEUE (PLAYLIST / ANTREAN VIDEO)
-- ==============================================================================
create table if not exists public.room_queue (
  id uuid default gen_random_uuid() primary key,
  room_id uuid references public.rooms(id) on delete cascade,
  media_type text check (media_type in ('youtube', 'direct_url')) not null,
  media_url text not null,
  title text not null,
  thumbnail_url text,
  added_by_user_id uuid references public.profiles(id) on delete set null,
  added_by_user_name text not null,
  order_index integer default 0,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

create index if not exists idx_room_queue_room_id on public.room_queue(room_id, order_index asc);

alter table public.room_queue enable row level security;

create policy "Queue dapat dibaca oleh siapa saja di room" 
  on public.room_queue for select using (true);

create policy "Semua pengguna dapat menambah ke antrean" 
  on public.room_queue for insert with check (auth.role() in ('authenticated', 'anon'));

create policy "Pengguna dapat mengupdate atau reorder antrean" 
  on public.room_queue for update using (auth.role() in ('authenticated', 'anon'));

create policy "Semua pengguna dapat menghapus antrean" 
  on public.room_queue for delete using (auth.role() in ('authenticated', 'anon'));

alter table public.room_queue replica identity full;

-- 8. AKTIFKAN SUPABASE REALTIME REPLICATION
-- Mengizinkan tabel didengarkan secara real-time via WebSocket
begin;
  -- Hapus publikasi jika sudah ada untuk menghindari duplikasi
  drop publication if exists supabase_realtime;
  create publication supabase_realtime for table public.rooms, public.room_messages, public.room_participants, public.room_queue;
commit;

-- Pastikan payload DELETE berisi data lengkap (replica identity full)
alter table public.rooms replica identity full;

-- 9. RPC FUNCTION: NTP SERVER CLOCK SYNC
-- Mengembalikan waktu UTC server saat ini untuk kompensasi clock drift
create or replace function public.get_server_time()
returns timestamp with time zone as $$
  select timezone('utc'::text, now());
$$ language sql stable;

grant execute on function public.get_server_time() to anon, authenticated;

-- ==============================================================================
-- 10. QUERY PERBAIKAN / MIGRATION (JALANKAN JIKA DATABASE SUDAH DIBUAT SEBELUMNYA)
-- ==============================================================================
-- alter table public.rooms add column if not exists host_name text;
-- alter table public.rooms replica identity full;
-- create policy "Semua pengguna dapat menghapus room" on public.rooms for delete using (auth.role() in ('authenticated', 'anon'));
-- create policy "Semua pengguna dapat menghapus peserta room" on public.room_participants for delete using (auth.role() in ('authenticated', 'anon'));
-- create policy "Semua pengguna dapat menghapus pesan room" on public.room_messages for delete using (auth.role() in ('authenticated', 'anon'));
-- create table if not exists public.room_queue (id uuid default gen_random_uuid() primary key, room_id uuid references public.rooms(id) on delete cascade, media_type text check (media_type in ('youtube', 'direct_url')) not null, media_url text not null, title text not null, thumbnail_url text, added_by_user_id uuid references public.profiles(id) on delete set null, added_by_user_name text not null, order_index integer default 0, created_at timestamp with time zone default timezone('utc'::text, now()));
-- alter table public.room_queue enable row level security;
-- create policy "Queue dapat dibaca oleh siapa saja di room" on public.room_queue for select using (true);
-- create policy "Semua pengguna dapat menambah ke antrean" on public.room_queue for insert with check (auth.role() in ('authenticated', 'anon'));
-- create policy "Pengguna dapat mengupdate atau reorder antrean" on public.room_queue for update using (auth.role() in ('authenticated', 'anon'));
-- create policy "Semua pengguna dapat menghapus antrean" on public.room_queue for delete using (auth.role() in ('authenticated', 'anon'));
-- alter table public.room_queue replica identity full;

-- ==============================================================================
-- 11. FUNGSI PEMBERSIHAN OTOMATIS: CLEANUP EXPIRED / ZOMBIE ROOMS & CHATS
-- ==============================================================================
-- Fungsi ini membersihkan room yang sudah ditinggalkan atau tidak aktif lebih dari X jam.
-- Karena tabel room_messages, room_participants, dan room_queue memiliki 
-- ON DELETE CASCADE, semua riwayat chat & data terkait akan otomatis ikut terhapus.
create or replace function public.cleanup_expired_rooms(hours_old int default 12)
returns int as $$
declare
  deleted_count int;
begin
  delete from public.rooms
  where updated_at < (now() - (hours_old || ' hours')::interval);
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$ language plpgsql security definer;

grant execute on function public.cleanup_expired_rooms(int) to authenticated, service_role;

-- Contoh jika menggunakan extension pg_cron di Supabase (jalankan setiap jam):
-- create extension if not exists pg_cron;
-- select cron.schedule('cleanup-zombie-rooms', '0 * * * *', 'select public.cleanup_expired_rooms(12);');


