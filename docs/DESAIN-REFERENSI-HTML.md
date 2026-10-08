# Acuan Desain — Katalog HTML (untuk redesain "Kasir ala katalog")

Diambil dari `lib/core/services/order_page_service.dart` (CSS/JS katalog).
Tujuan: landasan redesain radikal layar Kasir Flutter — tetap di dalam
Flutter + Material 3 (ThemeData, komponen Material, GoRouter), tanpa
library UI pihak ketiga.

## 1. Token visual
| Token | Terang | Gelap |
|---|---|---|
| accent / accent-2 | #C96442 / #D97757 | sama |
| canvas (latar) | #EBE8E0 | #161412 |
| panel | #FBFAF7 | #211E1C |
| card | #FFFFFF | #2A2623 |
| ink / ink-2 / ink-3 | #2A2824 / #6C685F / #9D988B | #ECE7DD / #A8A298 / #726C63 |
| line (garis) / field | #E7E2D7 / #F1EEE7 | #383330 / #1C1917 |
| ok / warn / danger | #4F7B5E / #B9702B / #C03A3A | #6FA380 / #D39A52 / #E0685F |
| accsoft | rgba(201,100,66,.13) | rgba(224,133,95,.16) |
| blob1 / blob2 | rgba(242,184,160,.55) / rgba(246,217,168,.5) | rgba(150,72,46,.42) / rgba(130,100,44,.30) |
Radius: kartu 14, tombol 11; dominan **pil (999)** 23x, lingkaran (50%) 8x, 12/14/16/18/20/22 untuk panel & sheet (sheet atas 30).
Bayangan: lembut hangat `0 6 24 rgba(90,60,30,.12)` (kartu mengambang), `0 4 12 rgba(201,100,66,.35)` (logo/tombol aksen), `0 8 22 rgba(0,0,0,.22)` (FAB/popup), `0 2 6 .15`.
Font: Hanken Grotesk (UI) + Newsreader (judul/angka). Tangga ukuran teks: 11.5/12/12.5/13/13.5/14/15/16/17/26 px.

## 2. Tata letak
- Satu halaman, dua keadaan (`data-view`): **landing** (sapaan serif 27px, kolom cari besar di tengah, chip kategori terpusat, "saran terlaris" sbg placeholder berganti) dan **daftar** (header mengecil 42->35px, kolom cari MENEMPEL di atas, chip kategori satu baris).
- Kolom cari TIDAK pernah dipindah DOM-nya (fokus & kursor aman). Transisi landing<->daftar memakai FLIP: layout berganti sekali, elemen yang bergeser dianimasikan hanya transform/opacity.
- Blob warna lembut di latar (radial 260/240px) yang meredup (opacity .5) di mode daftar.
- Tombol pesanan melayang bawah: pecah 3/4 "Lihat Pesanan" + 1/4 "Kosongkan" (merah); label menyusut saat scroll.
- Sheet/modal produk: gaya struk/tipografis (MOCKUP B); tutup dengan geser turun + tombol X.

## 3. Gerak
Kurva: `cubic-bezier(.22,.61,.36,1)` (--ease, halus mendarat), `(.3,1.25,.45,1)` (12x, memantul kecil), `(.3,1.4,.5,1)`, `(.2,.8,.2,1)`. Durasi umum 0.28-0.3 s; fade overlay .28 s. ~45 transisi/animasi CSS. Stiker Lottie memutar berulang hanya saat terlihat (IntersectionObserver) & berhenti bila tab tersembunyi/`prefers-reduced-motion`.

## 4. Pola interaksi
Placeholder saran berganti (kolom cari "hidup"); tap saran = cari langsung; Enter/panah = cari; X = bersihkan; riwayat browser: masuk daftar = satu entri sehingga Kembali ke landing; keyboard HP: `revealSearch` menggulirkan agar kolom cari tak tertutup; konfirmasi inline (Ya/Tidak) alih-alih dialog untuk aksi ringan.

## 5. Status penerapan di Flutter (8 Okt 2026)
Sudah: palet & radius 14/11 di `AppTheme`, font ganda, landing Kasir (sapaan serif, cari besar, chip kategori, Terlaris/Terakhir), stiker .tgs, token gerak `AppMotion`.
Belum: blob latar, kolom cari yang pindah ke atas (FLIP), header toko ringkas, tombol aksi melayang, kartu pesanan 3/4+1/4 di cart bar, sheet gaya struk di kasir, saran terlaris berganti sbg placeholder.
