# Rules & Panduan Pengembangan Proyek Nobarin

File ini berisi panduan, konvensi kode, dan arsitektur wajib untuk agen AI dan developer yang berkontribusi pada repositori **Nobarin**.

---

## 1. Ikhtisar Proyek & Tech Stack

**Nobarin** adalah aplikasi Watch Party multi-platform (Android, iOS, Web, Windows, macOS, Linux) untuk menonton video secara bersamaan (*synchronized playback*) dengan fitur Text Chat dan Voice Chat (VoIP) real-time.

- **Framework**: Flutter (Dart SDK `^3.13.2`)
- **State Management**: `flutter_riverpod` (`^3.4.3`)
- **Routing & Navigasi**: `go_router` (`^18.0.1`)
- **Backend & Database**: `supabase_flutter` (`^2.17.2`) (Auth, PostgreSQL, Realtime Broadcast & Presence)
- **VoIP & Audio**: WebRTC (`flutter_webrtc`), SFU Architecture (LiveKit)
- **Video Engine**: `media_kit`, `media_kit_video` (native platforms), `youtube_player_iframe`, `webview_flutter`
- **Design System**: Dark Neon & Atmospheric Void (`AppColors`, `AppTheme`, Glassmorphism)

---

## 2. Struktur Direktori & Arsitektur Kode (Feature-First)

Struktur kode wajib mematuhi pola **Feature-First**:

```text
lib/
├── app.dart                       # Root MaterialApp & routing setup
├── main.dart                      # Bootstrap & inisialisasi platform/backend
├── core/                          # Kode yang digunakan lintas fitur
│   ├── constants/                 # AppColors, ApiConstants, dll.
│   ├── errors/                    # Failure & exception classes
│   ├── network/                   # SupabaseClient, HttpClient, P2P/LAN services
│   ├── routes/                    # GoRouter configuration
│   ├── theme/                     # AppTheme & visual styling
│   ├── utils/                     # NtpClockSync, time formatters, haptics
│   └── widgets/                   # Shared UI (FrostedGlassBox, ShimmerLoading)
└── features/                      # Domain spesifik fitur
    ├── auth/                      # Login guest/email & user profile
    ├── browser/                   # Web browser & video detector
    ├── chat/                      # Real-time chat & reactions
    ├── lobby/                     # Public lobby & room discovery
    ├── pip/                       # Picture-in-Picture mode
    ├── room/                      # Video player, sync engine, room controllers
    ├── screenshare/               # Screen sharing controls
    └── voice/                     # Voice chat (VoIP) & microphone visualizer
```

### Aturan Arsitektur:
1. Setiap fitur baru harus diletakkan di dalam `lib/features/<nama_fitur>/` dengan subdirektori modular (`controllers/`, `models/`, `presentation/`, `data/`, atau `services/`).
2. Jangan menaruh logika bisnis atau state management langsung di dalam widget presentation. Gunakan Riverpod Notifier/AsyncNotifier.
3. Widget UI umum yang dipakai lebih dari satu fitur harus ditaruh di `lib/core/widgets/`.

---

## 3. Aturan State Management (Riverpod)

1. **Konsistensi Provider**:
   - Gunakan `ConsumerWidget` atau `ConsumerStatefulWidget` saat membutuhkan akses ke `WidgetRef`.
   - Gunakan `ref.watch` di dalam method `build` untuk me-render UI secara reaktif.
   - Gunakan `ref.read` hanya di dalam event handler/callback (misal: `onTap`, `onPressed`).
2. **Manajemen Siklus Hidup & Memory Leak**:
   - Selalu bersihkan resource menggunakan `ref.onDispose(...)` pada provider (misal: membatalkan `StreamSubscription`, menutup Supabase channel, mendispose video controller atau WebRTC peer connection).
   - Gunakan `.autoDispose` pada provider yang datanya hanya relevan saat layar aktif.

---

## 4. Multi-Platform & Web Safety

Aplikasi ini menargetkan Mobile, Web, dan Desktop. Perhatikan pembatas platform:
1. **Guard Platform Native**:
   - Modul yang memerlukan native binary atau C FFI (seperti `media_kit`, `flutter_background`) **wajib** dipagari dengan pengecekan platform:
     ```dart
     if (!kIsWeb) {
       MediaKit.ensureInitialized();
     }
     ```
2. **Platform Web**:
   - Hindari import `dart:io` secara langsung pada file yang diakses oleh Web. Gunakan `package:http`, `universal_io`, atau pengecekan `kIsWeb`.
   - Ketika menumpuk overlay UI di atas iframe/player Web, gunakan `PointerInterceptor` untuk mencegah klik terserap oleh elemen web native.
3. **Responsive UI**:
   - Desain UI harus responsif dan adaptif terhadap layar smartphone (portrait), layar tablet/desktop (landscape/split screen), dan mode fullscreen player.

---

## 5. Playback Sync Engine & Realtime Best Practices

1. **NTP Clock Synchronization**:
   - Perhitungan drift video wajib menyertakan selisih waktu server via `NtpClockSync().offsetMs` agar tidak terpengaruh oleh jam lokal perangkat pengguna yang tidak akurat.
2. **Throttling Event Broadcast**:
   - Jangan memancarkan event `SYNC_STATE` atau posisi seek secara berlebihan (rapid firing). Gunakan debouncing/throttling saat pengguna menggeser slider seek.
3. **Channel Cleanup**:
   - Setiap kali pengguna meninggalkan room, pastikan channel Supabase Realtime di-unsubscribe dan diputus agar tidak terjadi memory leak dan traffic websocket berlebih.

---

## 6. UI & Design System (Atmospheric Dark & Neon)

1. **Gunakan Token Warna Konsisten**:
   - Wajib menggunakan warna dari `AppColors` (misal: `AppColors.background`, `AppColors.surface`, `AppColors.primaryNeon`, `AppColors.secondaryNeon`).
   - Dilarang keras melakukan hardcode nilai `Color(0x...)` baru di file widget jika warna tersebut sudah memiliki token di `AppColors`.
2. **Glassmorphism & Surface Elevation**:
   - Manfaatkan `FrostedGlassBox` untuk komponen floating dialog atau overlay kontrol video.
   - Gunakan gradient preset seperti `AppColors.primaryGradient` atau `AppColors.heroGradient` untuk tombol utama dan aksen neon.

---

## 7. Kualitas Kode, Lints & Debugging

1. **Lint Rules**:
   - Ikuti aturan `analysis_options.yaml` (`package:flutter_lints/flutter.yaml`).
   - Gunakan `const` constructor sesering mungkin untuk meminimalkan rebuild widget yang tidak perlu.
2. **Logging**:
   - Dilarang menggunakan raw `print()` di production code.
   - Gunakan `debugPrint('[NamaKomponen] Pesan log')` atau logger terstruktur.
3. **Error Handling**:
   - Bungkus operasi asinkron kritis (network request, parsing video URL, WebRTC handshake) dengan `try-catch`.
   - Berikan feedback visual yang ramah kepada pengguna (misal: SnackBar/Banner notifikasi) saat terjadi kegagalan jaringan atau parsing stream.

---

## 8. Keamanan & Environment Variables

1. **Kredensial & Secrets**:
   - Jangan pernah melakukan commit file `.env` atau hardcode secret key (service role key, private API keys) ke dalam repositori git.
   - Akses konfigurasi Supabase melalui environment variable atau `ApiConstants`.

---

## 9. Kepatuhan Kebijakan Google Play Store (Google Play Policy Compliance)

Setiap pengembangan fitur wajib mematuhi *Google Play Developer Program Policies* agar aplikasi lolos review dan tidak terkena penolakan atau *takedown*:

1. **Prinsip Hak Akses Minimal (*Least Privilege Permissions*)**:
   - **Mikrofon (`RECORD_AUDIO`)**: Hanya minta izin saat runtime (*just-in-time*) ketika pengguna secara aktif menekan tombol mic/voice chat. Dilarang meminta izin mikrofon saat aplikasi pertama kali dibuka (*app startup*). Sediakan penjelasan singkat (*in-app rationale*) sebelum dialog sistem muncul.
   - **Penyimpanan (Scoped Storage)**: Wajib menggunakan Scoped Storage (Android 10+) dan media picker modern (`file_picker`, Android Photo/Video Picker). Dilarang meminta izin broad seperti `MANAGE_EXTERNAL_STORAGE` atau legacy `READ_EXTERNAL_STORAGE` tanpa justifikasi ketat.
   - **Notifikasi (`POST_NOTIFICATIONS`)**: Permintaan izin notifikasi pada Android 13+ (API 33+) harus dilakukan secara kontekstual dengan edukasi manfaat kepada pengguna.
   - **Foreground Services (Android 14+ / API 34+)**:
     - Setiap Foreground Service (misal background VoIP atau audio streaming via `flutter_background`) wajib mencantumkan atribut `android:foregroundServiceType` yang sesuai di `AndroidManifest.xml` (contoh: `microphone`, `mediaPlayback`).
     - Wajib menampilkan notifikasi persisten yang jelas dan informatif saat service berjalan.

2. **Kebijakan Konten Buatan Pengguna (*User-Generated Content / UGC*)**:
   - Karena Nobarin menyediakan fitur Text Chat real-time dan Public Room, aplikasi wajib menyediakan:
     - **Terms of Service (EULA) & Community Guidelines**: Pernyataan tegas bahwa pelecehan, ujaran kebencian, konten ilegal, dan pornografi tidak ditoleransi.
     - **Mekanisme Pelaporan (*In-App Reporting/Flagging*)**: Tombol untuk melaporkan pesan, room, atau pengguna yang melanggar.
     - **Fitur Blokir & Mute (*Block & Mute*)**: Opsi bagi pengguna untuk memblokir atau membisukan pengguna lain yang mengganggu secara instan.
     - **Kontrol Moderasi Host**: Kemampuan bagi host room untuk mengeluarkan (*kick*) atau membisukan peserta yang bermasalah.

3. **Hak Cipta, Integritas Streaming, & YouTube ToS**:
   - **YouTube API Terms of Service**: Pemutaran video YouTube wajib menggunakan player iframe resmi (`youtube_player_iframe`). Dilarang keras mem-bypass iklan, melakukan *audio ripping*, atau memutar video YouTube saat layar mati/background yang melanggar persyaratan layanan YouTube.
   - **Anti-Pirasi / DMCA**: Jangan menyediakan fitur bawaan atau antarmuka yang secara eksplisit memfasilitasi pembajakan konten berhak cipta. Sediakan kanal pelaporan pelanggaran hak cipta.

4. **Penghapusan Akun & Keamanan Data (*Account Deletion & Data Safety*)**:
   - **Fitur Hapus Akun Mandiri**: Sesuai mandat Google Play, jika aplikasi mendukung pendaftaran/login (termasuk Supabase Auth), aplikasi **wajib menyediakan tombol penghapusan akun langsung di dalam aplikasi** serta tautan web eksternal untuk menghapus data pengguna.
   - **Enkripsi Data Transit**: Seluruh komunikasi jaringan wajib menggunakan protokol terenkripsi (HTTPS, WSS, WebRTC DTLS-SRTP).
   - **Transparansi Data Safety**: Seluruh pengumpulan data (ID akun, log crash, telemetri) harus terdokumentasi rapi agar akurat saat dideklarasikan di form Data Safety Google Play Console.

5. **Tautan Kebijakan Privasi (*Privacy Policy*)**:
   - Tautan URL Kebijakan Privasi yang aktif dan valid wajib tersedia di dalam aplikasi (misal di halaman login/profil/pengaturan) serta di halaman listing Google Play Store.

