# Doorprize Display

Aplikasi Windows sederhana untuk mengumumkan nomor doorprize di layar
proyektor. Operator mengetik nomor → nomor tampil besar di layar penonton,
menumpuk ke bawah.

- **Dua window**: Operator (input + kelola) dan Penonton (tampilan bersih
  untuk proyektor, otomatis pindah ke layar kedua + fullscreen).
- **Konsep ronde**: ketik nomor → Enter → numpuk di layar. Klik **Selesai**
  → ronde tersimpan ke **riwayat** (lengkap dengan waktu) dan layar
  dikosongkan untuk ronde berikutnya. Layar otomatis memuat sebanyak
  nomor yang diinput — tidak perlu atur jumlah baris.
- **Nomor tersimpan** di SQLite lokal — aman ditutup-buka aplikasi.
- **Nomor duplikat ditolak** otomatis (per ronde).
- **Judul layar** bisa diganti per acara (default "NOMOR DOORPRIZE").
- Tiap nomor bisa **diedit / dihapus** selama ronde berjalan.
- Nol depan aman (`012345` tidak jadi `12345`).

## Cara build manual di PC Windows

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
   (stable) dan jalankan `flutter doctor` sampai centang Windows Desktop.
2. Buka folder ini di terminal, generate runner Windows sekali saja:
   ```
   flutter create --platforms=windows .
   ```
3. **Wajib sekali saja** — daftarkan plugin untuk sub-window (layar penonton).
   Tanpa ini, window penonton tidak bisa fullscreen. Edit file
   `windows/runner/flutter_window.cpp`:
   - Tambahkan include di bagian atas:
     ```cpp
     #include "desktop_multi_window/desktop_multi_window_plugin.h"
     ```
   - Di dalam method `OnCreate()`, tepat setelah baris
     `RegisterPlugins(flutter_controller_->engine());` tambahkan:
     ```cpp
     DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
       auto* flutter_view_controller =
           reinterpret_cast<flutter::FlutterViewController*>(controller);
       auto* registry = flutter_view_controller->engine();
       RegisterPlugins(registry);
     });
     ```
4. Ambil package:
   ```
   flutter pub get
   ```
5. Jalankan:
   ```
   flutter run -d windows
   ```
6. Untuk file .exe rilis:
   ```
   flutter build windows --release
   ```
   Hasilnya di `build\windows\x64\runner\Release\`.

## Alur pakai

1. Jalankan `DoorprizeDisplay.exe` — window operator + penonton terbuka.
2. Atur **judul acara** bila perlu.
3. Ketik nomor → **Tambah** (atau Enter). Nomor muncul di layar penonton,
   menumpuk ke bawah.
4. Salah ketik → tombol **Edit** di baris nomor tersebut.
5. Ronde selesai → klik **Selesai** → ronde masuk riwayat, layar kosong
   untuk ronde berikutnya.
6. Cek nomor ronde lalu → bagian **Riwayat Ronde** di window operator.

## Build otomatis (GitHub Actions)

Push ke `main` → workflow *Build Windows Release* jalan: analyze + test +
build, hasilnya jadi artifact `.zip` (90 hari). Rilis versi via
*Run workflow* manual (pilih patch/minor/major) → tag + GitHub Release
dibuat otomatis.
