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
