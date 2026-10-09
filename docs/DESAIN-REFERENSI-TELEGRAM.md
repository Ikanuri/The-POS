# Acuan Desain — Telegram Android (untuk Prototype Redesign Flutter)

Hasil studi `github.com/DrKLO/Telegram` (clone dangkal, kode Java/View).
**Lisensi GPLv2: pelajari POLA & ANGKA saja — jangan salin kode/aset.**
Semua angka di bawah diukur dari kode (jumlah pemakaian di seluruh `ui/`),
bukan dari tangkapan layar. Satuan `dp` Android ≈ logical pixel Flutter.

## 1. Gerak — fondasi "rasa Telegram"

| Hal | Temuan | Pemakaian |
|---|---|---|
| Kurva dominan | `EASE_OUT_QUINT` (.23,1,.32,1) | **1130×** (DEFAULT .25,.1,.25,1 = 447×; EASE_OUT 176×; EASE_BOTH 47×; EASE_IN 28×; EASE_OUT_BACK 13×) |
| Durasi dominan | 150 ms (345×), 200 (216×), 250 (158×), 320 (147×), 180 (123×), 300/220/350/420 | tangga durasi pendek: **150-200-250-320** |
| Nilai UI | `AnimatedFloat` dipakai di **167 berkas** — hampir tak ada nilai UI yang berubah tanpa transisi | |
| Pegas | `SpringAnimation` hanya 35 berkas — pegas jarang; yang umum = kurva Bezier | |

Kesimpulan: satu kurva (easeOutQuint) untuk hampir segalanya + tangga durasi
kecil. Ini sudah kita terapkan di `AppMotion` (fast 120 / base 200 / medium 260 / page 300).

## 2. Umpan balik sentuh — "tombol yang memantul" (BELUM kita punya)

`ScaleStateListAnimator` dipasang di **±136 berkas** (hampir semua tombol/ikon/kartu):
- **Ditekan:** skala mengecil ke `1 − s` dalam **80 ms**.
- **Dilepas:** kembali ke 1 dalam **350 ms** dgn `OvershootInterpolator(tension)` (melewati 1 sedikit lalu mendarat = memantul).
- Nilai `s`/tension yang dipakai: bawaan **0,1 / 1,5** (tombol besar); paling sering **0,02 / 1,2** (ikon & baris kecil); 0,025; 0,05.
- Haptik: `KEYBOARD_TAP` **172×**, `LONG_PRESS` 70× (ketukan = tik halus, tahan = getar lebih tegas).

Pemetaan Flutter: widget `PressScale` (Listener + AnimationController; turun 80 ms, naik 350 ms `Curves.easeOutBack`-like). Skala 0,02-0,05 untuk baris/ikon, 0,1 hanya tombol utama.

## 3. Angka berubah (relevan utk POS: qty, total, badge)

- **CounterView (badge):** muncul 220 ms `Overshoot`; hilang 150 ms; **ganti angka 430 ms**; saat naik skala membengkak +10% di separuh pertama (EASE_OUT) lalu kembali (EASE_IN).
- **AnimatedNumberLayout:** digit lama keluar ke atas/bawah (translasi setinggi baris + alpha) 150 ms; digit baru masuk dari sisi berlawanan.
- Kita sudah punya `BumpOnChange` (denyut) — langkah berikut yang lebih "Telegram": roll per digit / pembengkakan 10%.

## 4. Lapisan sementara

| Elemen | Temuan |
|---|---|
| BottomSheet | buka **320 ms EASE_OUT_QUINT**, tutup **220 ms DEFAULT**; bayangan gelap (dim) ikut 320 ms; padding atas 8 dp |
| Popup menu | masuk **150 + 16×jumlah-item ms** (menu panjang sedikit lebih lama), decelerate, **tumbuh dari sudut pemicu** (skala mulai 0,5 dari titik jangkar) |
| Dialog | radius sudut ~18-20 dp, padding isi 23 dp |
| Bulletin (toast) | masuk `easeOutQuad`, keluar **175 ms** `easeInQuad`; durasi tampil 1,5 / 2,75 / 5 dtk; dapat digeser keluar (translasi X + alpha 200 ms) |
| Halaman | masuk: translasi X **48 dp → 0** + alpha 0 → 1; keluar kebalikannya (sudah kita terapkan) |

## 5. Daftar & memuat

- **Item animator daftar** (`DialogsItemAnimator`): tambah/hapus/ubah **180 ms** decelerate (alpha + translasi), item lain bergeser mulus — bukan lompat.
- **Daftar pertama muncul:** `RecyclerItemsEnterAnimator` ~200 ms (item masuk berurutan).
- **Kosong:** `emptyView` fade+skala 150 ms.
- **Memuat:** `FlickerLoadingView` = kerangka (skeleton) bergradien bergerak: lingkaran avatar r=28, dua-tiga bar teks tinggi 8 dp radius 4 dp; header 32 dp. Bukan spinner.

## 6. Ukuran & tipografi (konsistensi, bukan kreativitas)

- **Teks:** 16 sp (71×), 14 (54×), 13 (39×), 15, 12, 17, 20 — **tangga kecil**: 12/13/14/15/16/17/20.
- **Avatar daftar:** 52-56 dp; tinggi baris dialog ~72-76; sel pengaturan 50-64 dp.
- **ActionBar:** 56 dp. **Radius:** gelembung/kartu 12-20; bar skeleton 4.
- **Avatar:** bulat bergradien dua warna, warna ditentukan oleh nama/id (tanpa gambar).
- **Pemisah:** garis tipis + blok "bayangan" abu antar kelompok pengaturan, bukan kartu berbingkai tebal.

## 7. Usulan terjemahan ke The POS (belum dikerjakan)

Urut berdasarkan dampak "rasa" per usaha, semuanya HANYA animasi (tanpa ubah layout/alur):
1. **`PressScale`** (tekan 80 ms ke 0,97-0,98; lepas 350 ms memantul) di baris produk, kartu, chip, tombol — dampak terbesar.
2. **Item animator daftar** (tambah/hapus baris keranjang, produk di hasil cari) 180 ms — sekaligus menutup task #37 (animasi keluar baris keranjang).
3. **Angka**: roll per digit atau bengkak +10% (qty, total, badge); ganti angka 430 ms utk perubahan besar.
4. **Skeleton** pengganti "…" / spinner saat memuat daftar.
5. **Popup menu** tumbuh dari titik ketuk (menu Kasir/Laci Meja saat tahan tab).
6. **Toast/bulletin** masuk-keluar 175-220 ms + bisa digeser.
7. **Haptik**: tik halus saat ketuk tombol utama, getar lebih tegas saat tahan (sekarang hanya 5 titik).
8. Keyboard: konten ikut bergeser mulus saat keyboard muncul (Telegram memakai AdjustPanLayoutHelper) — relevan utk kolom cari.

Semua harus menghormati `AppMotion.reduced` ("kurangi animasi") dan diuji di HP (rasa mulus tidak terbukti oleh test).

---

# Bagian 8-14 — Penggalian lanjutan (klon ulang 8 Okt 2026)

Diukur ulang dari klon dangkal `DrKLO/Telegram`. Pola & angka saja (GPLv2).

## 8. Mode performa — "animasi menyesuaikan HP" (PALING RELEVAN utk target kita)

- `SharedConfig.measureDevicePerformanceClass()` mengklasifikasi HP **LOW/AVERAGE/HIGH** sekali, dari: versi Android, jumlah CPU, frekuensi CPU maks (dibaca `/sys/.../cpuinfo_max_freq`), `memoryClass`, total RAM, dan daftar SoC lemah. **LOW** bila: CPU <=2 inti, memoryClass <=100, <=4 inti & <=1250 MHz, atau **RAM < 2 GB**. AVERAGE bila <8 inti / memoryClass <=160 / <=2055 MHz.
- Dipakai di **146 titik**: kelas LOW mematikan gradien latar, efek partikel, blur; blur hanya di HIGH.
- `LiteMode` = bendera fitur per jenis efek (emoji animasi, latar, blur, spoiler, partikel, autoplay) + **preset LOW/MEDIUM/HIGH** dan **hemat baterai otomatis** (efek mati saat baterai <= ambang, default dapat diatur pengguna).
- Pengguna bisa menimpa manual (menu "Penggunaan Daya").
- Terjemahan: `AppMotion.dur()` baru hormati "kurangi animasi" sistem. Tambah: kelas performa HP (RAM/CPU) -> matikan kilau skeleton & PressScale di HP lemah, + opsi manual di Pengaturan.

## 9. Geser baris (swipe) — aksi cepat di daftar

- `ItemTouchHelper` di daftar chat; ambang **45% lebar**, kecepatan lepas 3500; aksi bisa diatur pengguna (SwipeGestureSettings: arsip/bisukan/hapus/baca/sematkan).
- Latar berwarna + ikon beranimasi mulai saat geser > **43 dp**; saat melewati ambang, latar "membasahi" (reveal) + **haptik KEYBOARD_TAP tepat satu kali** di titik lewat ambang (bukan terus-menerus).
- Terjemahan: kita sudah punya `Dismissible` di 9 berkas; yang belum: ambang & haptik di titik lewat, ikon beranimasi, latar reveal, aksi bisa diatur.

## 10. Mode seleksi (ActionMode)

- Tahan baris -> bar atas diganti bar aksi: **alpha 0->1 selama 200 ms**, ikon back berputar jadi X (`backDrawable.setRotation`), judul = jumlah terpilih (angka beranimasi), daftar boleh bergeser (`translationView`).
- Terjemahan: kita hanya 2 berkas yang punya mode seleksi. Potensi: aksi massal di Produk/Riwayat (hapus, ubah kategori). INI FITUR (ubah alur), bukan sekadar animasi -> butuh persetujuan.

## 11. Tombol aksi mengambang (FAB) & tab

- FAB **disembunyikan saat menggulir turun** (`goingDown`), muncul lagi saat gulir naik/berhenti; ambang gerak > 1 px; juga bersembunyi saat mode seleksi dan saat fragmen lain terbuka.
- Penanda tab (`FilterTabsView`): indikator meluncur **320 ms EASE_OUT_QUINT**; badge hitungan: angka lama keluar & baru masuk geser **15 dp** vertikal.
- Terjemahan: kita punya 3 FAB; sembunyi-saat-gulir murah dan jelas manfaatnya (tombol tak menutup baris terakhir).

## 12. Umpan balik — undo dan bulletin

- **UndoView** (26 layar) dipakai utk hapus/arsip: aksi LANGSUNG dijalankan, ada tombol "Urungkan" dengan hitung mundur **3-5 dtk** (bar waktu), masuk 250 ms / keluar 180 ms; **172 titik** `BulletinFactory` utk konfirmasi (salin, simpan, dll).
- Pola: **tidak bertanya "yakin?" dulu**, melainkan lakukan lalu beri kesempatan urungkan.
- Terjemahan: kita punya 5 berkas dengan "Urungkan"; sisanya masih dialog konfirmasi. Berisiko utk data keuangan (void transaksi) -> JANGAN ganti dialog konfirmasi utk aksi destruktif uang/stok; hanya cocok utk aksi ringan (hapus baris keranjang, kosongkan keranjang).

## 13. Haptik — angka sebenarnya

`KEYBOARD_TAP` 173x, `LONG_PRESS` 75x, `KEYBOARD_PRESS` 4x; `FLAG_IGNORE_GLOBAL_SETTING` 119x (tetap bergetar walau pengaturan sistem "umpan balik sentuh" mati) dan `FLAG_IGNORE_VIEW_SETTING` 53x. Aturan emas: tik halus utk ketuk/lewat ambang, getar tegas utk tahan. Ada helper tunggal (`AndroidUtilities.vibrate`).
- Perhatian: mengabaikan pengaturan sistem itu keputusan Telegram; utk kita sebaiknya MENGHORMATI pengaturan sistem + sakelar di Pengaturan app.

## 14. Visual statis

- **Token warna: 823 kunci** (`key_*`) — pewarnaan per komponen, bukan segelintir. Teks abu-abu **5 tingkat** (GrayText..GrayText5), merah teks reguler/tebal, hijau 2 tingkat. Kita: skema Material 3 + beberapa warna semantik; tingkatan abu-abu teks sekunder bisa dirapikan.
- **Kerapatan:** baris pengaturan **50 dp** + garis pemisah 1 px; menu popup baris **48 dp**, min lebar **196 dp**, padding horizontal 18 dp, radius 12; target sentuh dominan **48 dp**; kolom cari 36-44 dp.
- **Pemisah blok:** `ShadowSectionCell` (celah abu-abu antar kelompok) — sudah dicatat di bagian 6.
- **Empty view:** `StickerEmptyView` = ilustrasi animasi + judul + subjudul (jarak 12 dp) + tombol aksi (padding 45x12 dp, radius 8); loading muncul fade 150 ms; tata letak berpindah 250 ms.
- **Skala font:** pengguna memilih 12-30 (bawaan 16, tablet 18) lewat slider dengan pratinjau langsung; radius gelembung juga bisa diatur (17).
- **Blur** hanya di kelas HIGH (lihat bagian 8) — keputusan visual + biaya performa; JANGAN diterapkan tanpa kontrol.

## 15. Peta: sudah / belum / bertabrakan

| Aspek | Status di The POS | Catatan tabrakan |
|---|---|---|
| Mode performa & hemat baterai | Belum (hanya `disableAnimations`) | Positif besar utk HP kelas bawah; murni logika |
| Geser baris + haptik ambang | Sebagian (`Dismissible`) | Aksi destruktif uang tetap konfirmasi |
| Mode seleksi massal | Hampir tidak ada | Fitur baru, bukan animasi |
| FAB sembunyi saat gulir | Belum | Murah, aman |
| Undo ala UndoView | Sebagian | Jangan utk void transaksi/uang |
| Haptik tombol/tab | Belum (5 titik) | Hormati pengaturan sistem; sakelar app |
| Token abu-abu 5 tingkat | Belum | Menyentuh tema seluruh app |
| Blur / gradien / ikon khusus | Tidak | Visual; butuh mockup JPG + persetujuan |
| Slider ukuran font + pratinjau | Ada skala font | Cek: tabrakan dgn Newsreader utk angka |

---

# Bagian 16-23 — Tata letak & UX (penggalian 8 Okt 2026, tahap 3)

Fokus: struktur layar, navigasi, kerapatan, alur interaksi. Diukur dari kode
(`MainTabsActivity`, `DialogsActivity`, `DialogCell`, `BottomSheet`,
`AlertDialog`, `SettingsActivity`, `ProfileActivity`). Pola & angka saja.

## 16. Navigasi utama — bilah tab MELAYANG (glass pill)

- 5 tab (Chats, Contacts, Settings, Calls, Profile-avatar). Bilah **tidak menempel ke tepi**: tinggi **56 dp**, margin **8 dp** di semua sisi, **lebar maks 328 dp** (+margin) di tengah, sudut bulat penuh, latar kaca/blur (blur hanya di HP kelas HIGH).
- **Konten diberi padding bawah** setinggi bilah (`additionNavigationBarHeight = 56+16`) dan `clipToPadding=false` -> daftar menggulir DI BAWAH bilah, baris terakhir tetap bisa ditarik naik. FAB ikut naik (`additionFloatingButtonOffset = 56+8`).
- **Tahan tab = pemilih cepat** (Chats -> folder, Contacts -> urut, Calls -> filter, Profile -> ganti akun). Pola yang SAMA sudah kita pakai (tahan tab Kasir -> Laci Meja).
- Tab punya **counter/badge** beranimasi (titik "!" bila ada hal yang perlu perhatian).
- Posisi pindah: indikator tab terpilih meluncur 380 ms EASE_OUT_QUINT.
- Terjemahan: kita pakai `NavigationBar` Material 3 menempel di bawah (label, ikon). Bilah melayang = ubah tata letak global (semua layar perlu padding bawah) -> keputusan desain besar.

## 17. Daftar utama — kerapatan & dua mode

- Baris dialog **70 dp** (default) atau **76 dp** ("tiga baris"); avatar **52-56 dp**; garis pemisah **1 px** (bukan kartu). Pengguna BISA mengganti kerapatan (`useThreeLinesLayout`).
- Skema isi baris: nama (tebal) + waktu di kanan; baris kedua = pratinjau; badge hitung di kanan bawah. Satu "judul + satu baris pendukung" — sangat konsisten.
- Terjemahan: daftar produk kita punya kartu/baris dgn banyak info (harga, stok, varian). Opsi "kerapatan" (kompak/nyaman) belum ada; layak utk HP kecil.

## 18. Pencarian

- Ikon cari di bilah atas membuka **kolom cari yang menggantikan bilah** (150 ms), bukan layar baru. Di bawahnya: **tab hasil** (Chat, Media, Tautan...), **pencarian terakhir** (carousel avatar 80x86 dp), saran.
- Terjemahan: kolom cari kasir kita sudah inline. Yang belum: **riwayat pencarian terakhir** & saran produk/pelanggan terakhir dipakai (cocok utk kasir yang mengulang barang sama).

## 19. Header yang menciut & "snap"

- Profil/Pengaturan: kartu header besar (avatar, nama, tombol aksi) **menciut saat menggulir**; bila berhenti di tengah, otomatis **snap** (`smoothScrollBy` EASE_OUT_QUINT) ke posisi penuh atau tertutup (ambang 60%). Daftar pengaturan diberi padding atas 12 dp dari status bar; header BUKAN bagian layar terpisah.
- Baris aksi cepat (Pesan, Bisukan, Panggil...) = satu deret tombol ikon+label di bawah nama.
- Terjemahan: layar Pengaturan/Detail Pelanggan/Detail Produk kita bisa memakai header menciut + deret aksi cepat. Kasir tidak butuh (layar sudah padat).

## 20. Lembar bawah (bottom sheet) & dialog — ukuran

- Sheet: padding atas **8 dp**, padding bawah **8 dp**, **lebar maks 500 dp** (layar lebar: 80%), tutup dgn **geser turun** (VelocityTracker: lepas cepat = tutup, lambat = kembali), ketuk di luar menutup. Judul sheet 16 dp horizontal (21 bila besar). Ada deteksi keyboard (>20 dp) -> tinggi sheet menyesuaikan.
- Dialog: padding isi **23 dp**, tombol tinggi **48 dp**, **lebar maks 356 dp** (446/496 utk layout khusus) -> dialog sempit & fokus.
- Terjemahan: aturan 360-dp di CLAUDE.md (tombol dalam `AlertDialog` overflow) selaras: Telegram menyusun tombol dgn lebar terukur. Lebar maks 500 dp utk sheet = bagus utk tablet/landscape kita.

## 21. FAB & tombol kirim

- FAB menghilang saat gulir turun, muncul saat naik/berhenti (bagian 11); terangkat sebesar tinggi bilah tab; bersembunyi saat mode seleksi.
- Kolom ketik: **satu tombol berubah bentuk** (mikrofon <-> kirim) tergantung isi; tooltip/penguncian rekaman. Terjemahan: tombol "Bayar"/"Tambah" kita bisa berubah label/ikon sesuai konteks tanpa pindah tempat (mis. "Tahan" vs "Bayar").

## 22. Keyboard & ukuran adaptif

- `SizeNotifierFrameLayout` memantau tinggi keyboard; layar menyesuaikan padding secara berkelanjutan (bukan loncat). Sheet/dialog dan kolom ketik menghitung ulang tiap frame.
- Terjemahan: Flutter sudah memberi `viewInsets` per frame; yang perlu dicek hanya layar yang memakai `Scaffold(resizeToAvoidBottomInset)` + `ListView` panjang agar baris aktif tetap terlihat.

## 23. Peta tata letak/UX: sudah / belum / bertabrakan

| Pola | Telegram | The POS | Penilaian |
|---|---|---|---|
| Tab melayang (glass pill) | 56 dp, margin 8, maks 328 | `NavigationBar` M3 menempel | Ubah global; keputusan desain besar, uji di tablet |
| Padding bawah = tinggi bilah, `clipToPadding=false` | ya | sebagian (FAB/cart bar) | Positif: baris terakhir tak tertutup |
| Tahan tab = pemilih cepat | ya | ADA (tab Kasir) | Perluas ke tab lain (Produk: kategori; Laporan: rentang) |
| Kerapatan baris dapat diatur | 70/76 dp | tetap | Opsi kompak utk HP kecil |
| Pencarian terakhir/saran | ya | belum | Positif utk kasir (barang berulang) |
| Header menciut + snap | ya | tidak | Hanya utk layar detail; bukan kasir |
| Sheet lebar maks 500 dp + geser tutup | ya | sheet penuh lebar | Cek tablet/landscape |
| Dialog lebar maks ~356 dp | ya | bawaan M3 (280-560) | Selaras aturan 360 dp |
| Tombol berubah bentuk menurut konteks | ya (mic/kirim) | label statis | Kandidat di Kasir (Bayar/Tahan) |
| Blur/kaca | HIGH saja | tidak | Butuh mode performa dulu (bagian 8) |
| Baris pemisah 1 px, tanpa kartu | ya | kartu + bayangan | Gaya; butuh mockup JPG + persetujuan |

**Ketidakcocokan mendasar:** Telegram = aplikasi MEMBACA/menggulir daftar
(informasi sama berulang). POS = aplikasi MENGETIK/mengetuk cepat dgn uang
(salah ketuk = rugi). Maka pola yang meningkatkan kecepatan/orientasi (padding
bilah, pencarian terakhir, tahan-tab, kerapatan) aman; pola yang menyembunyikan
elemen (FAB hilang saat gulir, header menciut) atau melakukan-dulu-tanya-nanti
(undo) HARUS dipilah per layar, terutama yang menyentuh uang/stok.

## 21. Grafik (org.telegram.ui.Charts) — analisis & penerapan (9 Okt 2026)

Sumber: `Charts/BaseChartView`, `LinearChartView`, `BarChartView`, `StackLinearChartView`, `PieChartView`, `ChartPickerDelegate`, `view_data/ChartHorizontalLinesData`, `LegendSignatureView`, `ChartData`. ~5900 baris.

**Pola yang ditemukan**
| Pola Telegram | Rincian terukur | Status di The POS |
|---|---|---|
| Garis bantu angka bulat | 6 garis (0..5), langkah `ceil(max/5)` dibulatkan ke kelipatan 10; label **singkat** (`formatWholeNumber`: K/M/B) di ATAS garis, rata kiri DI DALAM area (tanpa lajur sumbu); garis memudar bila terlalu rapat | **Diterapkan**: `niceAxis` (langkah {1,2,2.5,5}x10^k) + `ChartGridPainter` + `abbrevNumber` (rb/jt/M/T) |
| Skala bergerak halus | `currentMaxHeight` -> `animateToMaxHeight` 400 ms FastOutSlowIn; garis bantu lama & baru cross-fade 200 ms | **Diterapkan** (400 ms `fastOutSlowIn`; garis & data memakai nilai animasi yang sama — cross-fade 2 set garis TIDAK ditiru, tak perlu) |
| Seleksi | garis tegak 1,5dp + titik 10dp berhalo warna latar + kartu `LegendSignatureView` (judul tebal 14, baris berwarna) yang PINDAH SISI di tengah layar, fade 200 ms; haptik waveform 2 ms tiap pindah indeks | **Diterapkan**: `StatsTrendChart` (garis, titik berhalo, kartu putih), `AppBarChart` + `ChartTooltipCard` (pindah sisi), `chartTick()` = `selectionClick` |
| Batang terpilih | batang lain di-blend ke warna latar (`blendColor`) mengikuti `selectionA` 200 ms; kelompok terpilih tetap penuh | **Diterapkan**: `AppBarChart` & grafik per jam Ringkasan (non-terpilih meredup) + geser (scrub) memindahkan pilihan |
| Gaya garis | stroke 2dp, join bulat, cap BULAT (cap PERSEGI bila >100 titik); tanpa kurva (segmen lurus) | **Diterapkan** (`isStrokeCapRound: n <= 100`, `isStrokeJoinRound`) |
| Label tanggal bawah | langkah kelipatan 2 (`highestOneBit << 1`), set lama/baru cross-fade, alpha memudar di tepi kiri/kanan | Sebagian: jumlah label dibatasi (<= ~6) via interval/`every`; fade tepi & cross-fade tidak |
| Pie | irisan terpilih "keluar", persen di tengah, legenda dgn centang | **Diterapkan**: `AppDonut` (irisan membesar, persen+nama di tengah, legenda meredup, haptik); menggantikan 5 donat duplikat |
| Picker (minimap + zoom rentang) | penggeser rentang dengan grafik mini 46dp, bayangan & pegangan 24dp | **TIDAK**: rentang tanggal sudah ada di header Laporan; minimap = ~600 baris, nilai rendah untuk 8–31 titik |
| Stack (batang/area bertumpuk), dua sumbu (kiri/kanan), "zoom ke jam" saat ketuk | | **TIDAK**: data kita tidak berseri-banyak bertumpuk |
| Kartu header dgn checkbox seri (nyalakan/matikan garis) | | **TIDAK** dulu: grafik kita 1–2 seri; legenda donat cukup |

Berkas: `lib/core/widgets/chart_kit.dart` (`abbrevNumber`, `niceAxis`, `ChartGridPainter`, `ChartTooltipCard`, `AppBarChart`, `AppDonut`, `chartTick`), `lib/features/laporan/stats/stats_common.dart` (`StatsTrendChart`). Test: `test/chart_kit_test.dart`.
