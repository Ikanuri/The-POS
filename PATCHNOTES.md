# Catatan Pembaruan (Patch Notes)

Ringkasan perubahan yang **dirasakan pengguna**, ditulis dalam bahasa sederhana.
Untuk catatan teknis lengkap per-commit, lihat [CHANGELOG.md](CHANGELOG.md).

> Yang dicantumkan di sini: fitur baru & perbaikan yang benar-benar terasa saat
> memakai aplikasi. Perbaikan internal/teknis tidak dicantumkan.

---

## 14 Juli 2026

### ✨ Fitur Baru
- **Katalog online kini menampilkan SEMUA satuan produk** — sebelumnya
  kalau sebuah produk punya lebih dari satu satuan jual (mis. "Sedap
  Goreng" per Biji dan per Dus), cuma satuan dasarnya yang tampil di
  katalog online; satuan lain (Dus) tidak pernah muncul sama sekali di
  jendela pilihan, sehingga pelanggan yang biasa beli per-dus tidak tahu
  opsi itu ada. Sekarang semua satuan tampil sebagai pilihan — termasuk
  kombinasi varian yang punya beberapa satuan sekaligus.
- **Tombol "Salin Teks Pesanan" di QR "Kirim ke Owner/Asisten"** —
  pegawai yang belum punya izin Terima Pembayaran sekarang punya jalur
  cadangan kalau scan QR susah (kamera bermasalah/pencahayaan kurang):
  salin teks pesanannya, lalu kirim manual lewat WhatsApp/Telegram ke
  owner/asisten, yang bisa langsung tempel di fitur "Tempel Pesanan".

### 🎨 Tampilan
- **Badge jumlah item di struk & keranjang kini bentuknya sama persis
  dengan badge di bar keranjang** (lingkaran terracotta berisi angka) —
  di struk, badge ini menempel di sudut kartu daftar barang; di
  keranjang, tampil di samping nominal Total.

### 🐛 Perbaikan Bug
- **Sync ke owner/asisten tidak lagi gagal total dengan pesan error
  teknis** (mis. "table transactions has no column named ...") kalau HP
  kasir belum sempat update ke versi app terbaru — data yang bisa
  disinkronkan tetap masuk, cuma bagian yang belum dikenal HP itu saja
  yang dilewati.

## 13 Juli 2026

### ✨ Fitur Baru
- **Pegawai kasir kini bisa "Kirim ke Owner/Asisten" tanpa pegang uang
  tunai.** Untuk pegawai yang belum diberi izin "Terima Pembayaran", tombol
  "Bayar" di keranjang berubah jadi "Kirim ke Owner/Asisten" — menampilkan
  kode QR berisi isi keranjang (termasuk nama pelanggan bila sudah
  dipilih pegawai). Owner/Asisten tinggal scan QR itu dengan scanner
  kasir yang sama (kamera atau scanner eksternal), pesanan otomatis
  masuk daftar antrian dengan tanda "Menunggu Anda Bayar" — judul
  kartunya nama pelanggan, dengan label kecil nama pegawai pengirim +
  jam masuk di atas kartu — siap diproses pembayarannya. Owner/Asisten
  sendiri tidak pernah digerbang — tetap langsung "Bayar" seperti biasa.
- **Verifikasi pesanan pegawai sebelum dibayar.** Tap pesanan "Menunggu
  Anda Bayar" di antrian sekarang membuka daftar barang dengan kotak
  centang — pegawai bacakan barang satu-satu, owner tinggal centang yang
  sudah dicek biar tidak ada yang kelewat/salah sebelum lanjut ke
  keranjang untuk diproses bayar. Centangan tersimpan otomatis, jadi kalau
  sempat tertunda pun tidak hilang.
- **Catatan per-produk di katalog HTML.** Saat memilih barang lewat
  katalog online, pelanggan sekarang bisa isi catatan untuk tiap produk
  (mis. "yang matang", "warna merah") — tidak cuma catatan umum untuk
  seluruh pesanan seperti sebelumnya. Catatan ini otomatis ikut ke
  keranjang & struk begitu kasir tempel pesanannya.
- **Katalog online: tap produk untuk pilih varian/jumlah/catatan.**
  Sebelumnya varian produk cuma bisa dibuka lewat tombol panah kecil yang
  di sebagian HP tidak responsif disentuh. Sekarang seluruh baris produk
  punya tombol bulat "+" (sama seperti di aplikasi kasir) untuk tambah
  cepat, atau bisa ditap untuk buka jendela pilihan — pilih ukuran/
  varian, atur jumlah (bisa diketik langsung, tidak cuma tombol +/-),
  dan isi catatan. Barang yang sudah dipilih bisa ditap lagi di keranjang
  untuk diubah tanpa perlu hapus & pilih ulang dari awal. Semua teks di
  halaman katalog juga diperbesar agar lebih mudah dibaca.
- **Batalkan Pembayaran.** Kalau ada pembayaran yang salah dicatat, kasir
  sekarang bisa membatalkannya langsung dari layar struk (dengan
  konfirmasi) — catatan pembayaran itu tetap tersimpan sebagai riwayat
  (ditandai "Dibatalkan"), tidak dihapus, jadi tetap ada jejaknya.
- **Ubah/hapus barang di struk yang belum lunas.** Selama nota masih
  berstatus kurang bayar (atau pembayarannya baru dibatalkan), kasir bisa
  tap barang di daftar struk untuk mengubah harga/jumlah/catatannya, atau
  menghapusnya — tanpa perlu buat nota baru dari awal.
- **Baris "Uang Diterima" di struk.** Kalau pelanggan bayar lebih dari
  tagihan (ada kembalian), struk sekarang menampilkan baris terpisah
  "Uang Diterima" yang menunjukkan jumlah uang yang benar-benar diserahkan
  pelanggan — sebelumnya baris "Dibayar" bisa membingungkan karena
  menampilkan angka bersih (setelah dikurangi kembalian), bukan uang yang
  diterima.
- **Checklist centang di keranjang kasir** — sebelum bayar, kasir sekarang
  bisa centang tiap barang di keranjang untuk memastikan barangnya sudah
  benar/lengkap (kotak centang di kiri nama barang). Centangan ini ikut
  terbawa ke struk, jadi tidak perlu mulai centang dari nol lagi di layar
  struk.

### 🎨 Tampilan
- **Tombol "Bayar" & "Tambah Belanjaan" kini sejajar** di layar struk
  (dulu ditumpuk vertikal terpisah) — tombol "Bayar" juga diganti warna
  hijau supaya lebih jelas bedanya dengan aksi lain.
- **Tombol "Uang Pas" di modal "Tambah Bayar"/pelunasan hutang pindah ke
  sebelah kiri tombol "Bayar"**, dan tombol "Bayar"-nya kini tidak bisa
  dipencet selama kolom nominal masih kosong — sama seperti kalkulator
  checkout utama.
- Nominal harga & angka di modal keranjang kasir sekarang pakai jenis
  huruf angka yang sama dengan layar lain di aplikasi (dulu beda font).
  Tombol tambah/kurang jumlah barang di keranjang & baris produk juga
  diperbesar supaya lebih mudah disentuh.
- **Tombol tambah/kurang jumlah barang di keranjang kini bentuknya sama
  persis dengan tombol di kartu produk** (lingkaran +/− berwarna), tidak
  lagi ikon ± polos. Tulisan nama barang, harga, dan catatan di keranjang
  juga sedikit diperbesar supaya lebih mudah dibaca.
- **Tombol "Uang Pas" pindah ke sebelah kiri tombol "Bayar"** di kalkulator
  bayar tunai — sebelumnya di atas keypad bareng pecahan uang, sekarang
  sebaris dengan "Bayar" supaya tidak salah pencet saat buru-buru.
- **Tombol "00" di keypad kalkulator bayar kini sebaris dengan "0"** (di
  baris paling bawah), bukan lagi di baris "7 8 9" — susunan angka jadi
  lebih rapi & mudah dijangkau.
- **Jumlah item kini tampil di struk & keranjang kasir** — di struk,
  jumlah barang tampil di sebelah kiri tombol "Tandai Semua"; di
  keranjang, jumlah barang tampil di samping nominal Total.

### 🐛 Perbaikan Bug
- **"Tap to Scan" tidak lagi mengulang barang yang sama.** Sebelumnya,
  setelah satu barang berhasil di-scan lewat mode "Tap to Scan", menekan
  tombol bidik lagi — walau barcode sudah disingkirkan dari kamera —
  kadang masih menambahkan barang yang SAMA sekali lagi ke keranjang
  (termasuk kasus kamera "kejar-mengejar" melaporkan barcode basi
  sesaat setelah dikonfirmasi). Sekarang tombol bidik otomatis nonaktif
  sampai ada barcode BARU yang benar-benar terdeteksi.
- **Scan pesanan pegawai (QR "Kirim ke Owner/Asisten") lewat scanner
  eksternal sekarang masuk antrian dengan benar**, tidak lagi salah
  kebuka sebagai "Tempel Pesanan" dan tidak lagi terasa lambat — termasuk
  untuk jenis scanner yang sebelumnya masih salah rute.
- **Tombol "Batalkan Pembayaran" sekarang selalu muncul di struk**, dulu
  cuma muncul untuk nota yang dicicil/dilunasi belakangan — nota tunai
  yang langsung lunas saat dibuat (paling umum) tidak pernah bisa
  dibatalkan pembayarannya sama sekali.
- **Aplikasi sekarang bisa dibuka di HP kelas bawah/lama yang sebelumnya
  langsung force-close tanpa keterangan** (dilaporkan terjadi di Infinix
  Smart 8, kemungkinan besar berlaku juga di HP sejenis). Penyebabnya
  sudah ditemukan: file APK sebelumnya tidak menyertakan komponen yang
  dibutuhkan HP dengan prosesor 32-bit — sekarang sudah disertakan.
  Ditambahkan juga menu **"Log Error Terakhir"** di Pengaturan →
  Diagnostik untuk membantu penelusuran kalau ada masalah serupa di
  kemudian hari.
- **Centang di struk (verifikasi barang diserahkan) sekarang tersimpan
  permanen** — sebelumnya kalau struk ditutup lalu dibuka lagi, semua
  centang hilang dan harus dicentang ulang dari nol.
- **Retur barang seharga Rp0 (mis. promo/bonus) sekarang bisa diproses**
  — sebelumnya gagal karena dianggap tidak valid.
- **"Sisa" di nota gabungan (struk pelanggan yang punya beberapa
  transaksi digabung jadi satu) tidak lagi tampil minus/salah hitung**
  saat kembalian sebelumnya dipakai lagi sebagai pembayaran — baik di
  layar, gambar yang dibagikan, maupun struk cetak fisik.
- **Tulisan di struk yang dibagikan lewat WhatsApp/dll kini tampil sama
  persis di semua HP** — sebelumnya jenis hurufnya bisa beda antara HP
  dan tablet karena mengikuti font bawaan tiap perangkat.
- **Harga di bawah nama produk (tab Produk) kini langsung ter-update**
  begitu harga produk itu diubah dari layar lain — sebelumnya harus
  keluar-masuk layar dulu supaya angkanya ikut berubah.
- **Modal "Tambah Bayar" dirapikan** — sebelumnya di beberapa ukuran layar
  tombol "Batal" tampil nempel sendiri di kanan atas sementara "Uang Pas"
  dan "Bayar" tidak sejajar (bahkan sempat hilang total di sebagian HP).
  Sekarang "Batal" di barisnya sendiri, "Uang Pas" & "Bayar" sejajar rapi
  di bawahnya. Judul modal ini juga disederhanakan jadi "Bayar" saja.

## 12 Juli 2026

### ✨ Fitur Baru
- **Kalkulator bayar Tambah Belanjaan sekarang menampilkan sisa tagihan
  lama.** Kalau nota masih punya kurang bayar dari sebelumnya, muncul baris
  "+ Sisa tagihan sebelumnya" plus baris "Total yang perlu ditagih" yang
  sudah dijumlahkan — kasir tinggal baca angkanya, tidak perlu menjumlah
  sendiri harga barang baru dengan sisa lama.
- **Harga dasar tampil di bawah nama produk** di tab Produk — tidak perlu
  buka detail produk cuma untuk lihat harganya.
- **Harga per-satuan tampil di keranjang kasir**, di bawah nama tiap item
  (mis. "Karung · Rp 65.000"). Berguna kalau qty lebih dari 1 dan mau tahu
  harga per 1 satuannya tanpa harus menghitung sendiri dari subtotal.
- **Tombol "Uang Pas"** di modal Tambah Bayar/Lunasi hutang — sekali tap
  langsung mengisi field dengan sisa tagihan persis, tidak perlu ketik
  manual.
- **Katalog HTML kini pakai font & tampilan yang sama dengan aplikasi**
  (Hanken Grotesk/Newsreader), selalu terang secara default (tidak lagi
  ikut mode gelap HP pelanggan yang bisa bikin teks susah dibaca).
- **Hapus produk langsung dari tab Produk** dengan geser (swipe) ke kiri,
  sama seperti di tab Pelanggan — tidak perlu lagi buka detail produk dulu.
- **Tanda cepat "Stok Habis"** — dari modal item kasir, tap ikon keranjang-
  silang untuk menandai produk habis. Produk tetap bisa ditambah ke
  keranjang seperti biasa (cuma tanda visual), tapi di katalog HTML
  statis tombol tambahnya benar-benar dinonaktifkan buat pelanggan.
- **Scanner kasir tampilan baru** — tombol tutup, senter, mode Sekali/
  Berulang, dan durasi pesan kini jadi kapsul-kapsul kecil melayang
  langsung di atas kamera (gaya kamera bawaan HP), bukan lagi tersembunyi
  di menu titik-tiga.
- **Mode "Tap to Scan"** (opsional, di kapsul scanner) — barcode yang
  terdeteksi kamera ditahan dulu, baru diproses setelah tap tombol bidik.
  Berguna kalau banyak barcode berdekatan di rak dan mode otomatis rawan
  salah pindai.
- Role device "Kasir" sekarang tampil sebagai **"Pegawai"** di semua layar
  Pengaturan & pairing (murni penamaan, tidak mengubah cara kerja).

### 🔧 Perbaikan
- **"Sisa Tagihan" di struk sekarang benar** saat kembalian yang sudah
  pernah diberikan dipakai lagi buat bayar belanja tambahan — sebelumnya
  angkanya lebih kecil dari yang seharusnya (uang yang sama sempat ke-hitung
  dua kali).
- **"Dibayar" di Ringkasan struk sekarang cocok dengan Sisa Tagihan** —
  sebelumnya Total tidak sama dengan Dibayar + Sisa Tagihan kalau kembalian
  sempat dipakai ulang.
- **Kalkulator bayar sekarang hitung Kembalian dengan benar saat masih ada
  sisa tagihan lama** — sebelumnya baris Kembalian, tombol "Uang Pas", dan
  daftar nominal cepat masih menghitung berdasarkan harga barang saja
  (belum termasuk sisa tagihan), jadi bisa tampil "kembalian" padahal
  sebenarnya masih kurang bayar.
- **Field harga produk sekarang bisa diketik lagi** setelah tap item di
  keranjang lalu tap tombol "Edit produk" — sebelumnya field harga cuma
  bisa dihapus, angka baru tidak bisa diketik sama sekali.

## 11 Juli 2026

### ✨ Fitur Baru
- **"Tempel Pesanan" bukan lagi fitur eksperimental** — badge "Eksperimental"
  di sheet-nya sudah dicabut, menyusul Katalog Pesanan (HTML) yang sudah
  lebih dulu jadi fitur resmi.
- **Kalkulator bayar di Tambah Belanjaan sekarang mengingatkan kembalian
  yang belum diambil.** Kalau nota masih ada kembalian nganggur dari
  pembayaran sebelumnya, muncul info nominalnya lengkap dengan centang
  "Pakai kembalian" — tinggal dicentang saat dipakai buat belanja
  tambahan, tidak perlu buka struk dulu untuk mencentangnya secara
  terpisah.
- **Riwayat kembalian per pembayaran di struk.** Nota yang dibayar lebih dari
  sekali (mis. bayar sebagian dulu, dilunasi belakangan) sekarang menampilkan
  kembalian tiap pembayaran secara terpisah di card "Riwayat Pembayaran",
  lengkap dengan centang "sudah diambil" masing-masing — tidak lagi ambigu
  "tadi bayar berapa? sisanya sudah dikembalikan belum?".
- **Buku Hutang: lihat daftar nota yang belum lunas.** Tap nama pelanggan di
  Buku Hutang sekarang menampilkan nota-nota mana saja yang masih menunggak
  (nomor, tanggal, sisa) — tap salah satunya langsung membuka struknya.
- **Menu baru: Import dari Griyo POS** (Pengaturan → Eksperimental). Khusus
  untuk migrasi data produk dari Griyo POS — sama dengan Import Produk CSV
  biasa, tapi bantuan formatnya disesuaikan untuk file export Griyo.
- **Katalog Pesanan (HTML) sekarang jadi fitur resmi**, tidak lagi berlabel
  "Eksperimental" — sudah cukup teruji untuk dipakai sehari-hari.

### 🔧 Perbaikan
- **Toggle "Izinkan Stok Minus" kembali ke halaman utama Pengaturan** —
  sebelumnya harus masuk ke Pengaturan → Izin Kasir dulu (baris paling
  bawah) untuk menemukannya.
- **Owner sekarang selalu bisa jual meski stok kurang/habis.** Sebelumnya
  owner ikut terblokir sama seperti kasir kalau "Izinkan Stok Minus"
  sedang dimatikan — sekarang owner tidak terpengaruh pengaturan itu,
  konsisten dengan hak akses owner lainnya.
- **Tombol "Harga lain" di modal produk (kasir) sekarang menampilkan nama
  harga yang sedang aktif** (mis. "Eceran"), bukan cuma angka hitungan
  generik — jadi jelas harga mana yang sedang dipakai.
- **Produk hasil import CSV tidak lagi hilang dari Katalog Pesanan (HTML).**
  Sebelumnya, produk yang masuk lewat import CSV (termasuk dari Griyo POS)
  tampil normal di tab Produk & kasir, tapi lenyap total saat katalog HTML
  dibagikan ke pelanggan — kini muncul dengan benar.
- **Import CSV dari Griyo POS sekarang berhasil.** Sebelumnya file export
  Griyo (pemisah kolom titik-koma) selalu gagal total — semua baris ditolak
  karena format kolomnya tidak dikenali. Sekarang terbaca otomatis, termasuk
  kolom Satuan & Grup Produk milik Griyo yang berupa kode angka (otomatis
  dipetakan ke satuan/grup yang benar seperti Pak, Dos, Slop — bukan
  diseragamkan jadi "Kg" untuk semua produk). Hasil import kini juga
  menandai produk dengan nama sama tapi kemasan berbeda (mis. sama-sama
  "234 12" untuk Slop & Pak) supaya mudah digabungkan manual bila perlu.

## 10 Juli 2026

### ✨ Fitur Baru
- **Tutup Kasir harian.** Menu baru (Pengaturan → Tutup Kasir) menampilkan
  rekap otomatis penjualan tunai, non-tunai, dan jumlah nota hari ini. Tinggal
  masukkan jumlah uang fisik di laci, dan aplikasi menghitung selisihnya
  (hijau = pas, merah = kurang, kuning/tosca = lebih). Tersimpan sebagai
  riwayat harian. (Beda dari "Tutup Buku" yang mengarsipkan transaksi tahunan.)
- **Pengingat backup.** Di Pengaturan → Backup & Restore kini ada kartu
  status "Backup terakhir: X hari lalu" (warnanya berubah makin lama makin
  merah) dan tombol "Pengingat Backup Otomatis" (interval harian/mingguan).
  Bila aktif, aplikasi mengingatkan lewat notifikasi kecil saat dibuka jika
  sudah lama tidak mencadangkan data.
- **Peringatan stok menipis.** Di pengaturan produk kini ada kolom "Stok
  Minimum" — isi angka ambangnya (kosongkan bila tidak ingin dipantau). Di
  tab Produk muncul chip "Stok Menipis (jumlah)" berwarna merah untuk
  menyaring produk yang stoknya sudah di bawah ambang, agar cepat tahu apa
  yang perlu segera di-restock.
- **Pilihan "Harga Lain" & grosir di kasir kini lebih rapi.** Saat menekan
  produk, harga grosir dan Harga Lain milik satuan yang dipilih dikumpulkan
  dalam satu tombol "Harga lain" di bawah kolom harga (dengan angka jumlah
  pilihan) — tidak lagi berupa deretan chip yang menumpuk saat opsinya banyak.
  Chip di atas kini khusus untuk memilih satuan.
- **Beralih antar pesanan tertahan lebih cepat (tanpa kehilangan).** Saat
  membuka pesanan tertahan lain sementara keranjang sedang berisi, keranjang
  yang aktif kini **otomatis ditahan balik** (pakai nama pelanggan bila ada,
  atau "Tanpa Nama + jam" untuk pembeli umum) — tidak lagi muncul peringatan
  "Ganti Keranjang?" dan tidak ada yang hilang. Mempercepat layani banyak
  pesanan sekaligus di jam sibuk.
- **Buku Hutang terpusat.** Di Laporan ada tab baru **Hutang** yang
  menampilkan semua pelanggan yang masih berhutang, diurutkan dari yang
  **paling lama menunggak** (warna berubah hijau→kuning→merah sesuai umur
  tunggakan). Ketuk nama pelanggan untuk melihat total hutang & langsung
  menekan **Lunasi** (bisa pilih metode bayar). Ada juga kolom cari nama.
- **Pencatatan Pengeluaran + Laba Bersih.** Ada menu baru Pengaturan →
  Pengeluaran untuk mencatat biaya (operasional, ambil pribadi, bayar
  supplier, uang keluar laci) lengkap dengan nominal, kategori, catatan, dan
  tanggal. Di Laporan (tab Ringkasan) kini muncul baris **Pengeluaran** dan
  **Laba Bersih** (= Laba Kotor − pengeluaran operasional & uang keluar laci;
  "ambil pribadi" dan "bayar supplier" tidak ikut dikurangi agar laba tidak
  salah hitung). Kasir bisa diberi izin mencatat pengeluaran lewat Izin Kasir.
- **Saat melunasi/menambah bayar hutang, kini bisa memilih metode bayar**
  (Tunai, transfer, QRIS, dsb) — sebelumnya semua pelunasan selalu tercatat
  sebagai "tunai" walau pelanggan membayar lewat transfer. Pilihan metode
  muncul di dialog Bayar di layar Struk, Riwayat Transaksi, dan Laporan.
- **Edit produk langsung dari layar Kasir.** Saat menekan produk di kasir,
  kini ada tombol edit (ikon pensil) di pojok modal — buka pengaturan produk
  itu tanpa harus pindah ke tab Produk. Hanya muncul untuk Owner & Asisten.
- **Metode pembayaran bisa diedit & dihapus.** Di Pengaturan → Metode
  Pembayaran, ketuk sebuah metode untuk mengubah namanya/detailnya, atau
  geser ke kiri untuk menghapus (metode harus dinonaktifkan dulu; "Tunai"
  tidak bisa dihapus). Sebelumnya metode hanya bisa ditambah & diaktif/
  nonaktifkan.
- **Urutan "Harga Lain" bisa diatur.** Di pengaturan produk (tab Produk),
  daftar Harga Lain sekarang punya ikon geser (drag-handle) di tiap baris —
  tahan lalu seret untuk mengubah urutannya. Urutan ini otomatis diikuti
  saat memilih harga lewat chip di kasir, jadi harga yang paling sering
  dipakai bisa ditaruh paling depan.

### 🐛 Perbaikan
- **Perhitungan varian di keranjang lebih akurat.** Bila satu produk masuk
  keranjang dalam beberapa satuan sekaligus (mis. per Dus dan per Pcs), varian
  yang dipilih kini menempel ke satuan yang benar — sebelumnya bisa "menyeret"
  hitungan satuan lain sehingga jumlah/stok terasa tidak pas.
- **Tombol kurang (−) tidak lagi salah mengurangi.** Kalau sebuah produk ada
  di keranjang dengan lebih dari satu satuan, menekan "−" di kartu produk kini
  memberi info untuk mengatur lewat keranjang (bukan diam-diam mengurangi
  satuan yang keliru).
- **Katalog Pesanan (halaman HTML untuk pelanggan) tidak lagi lag di HP
  low-end.** Pencarian produk dan tombol tambah/kurang jumlah kini jauh
  lebih responsif, terutama untuk toko dengan katalog besar.
- **Pencarian pelanggan di layar Bayar kini menampilkan semua hasil,
  bisa di-scroll.** Sebelumnya hanya 5–8 nama teratas yang ditampilkan,
  jadi pelanggan yang urutan namanya jatuh di belakang (mis. tidak muncul
  saat mengetik sebagian nama) bisa "hilang" dari daftar padahal sebenarnya
  ada.
- **Struk in-app: urutan jumlah & satuan dibalik jadi lebih wajar dibaca**
  ("1 pcs" alih-alih "pcs 1"), menyamakan dengan struk versi cetak/kirim
  yang memang sudah begitu.
- **Impor produk dari CSV: produk dengan nama & satuan sama tapi barcode
  berbeda tidak lagi terbuang diam-diam saat impor.** Ini penyebab kasus
  "Sedap Goreng per dus tidak ada" yang sempat dilaporkan — dua varian
  barang dengan barcode berbeda dianggap duplikat dan salah satu dibuang
  tanpa pemberitahuan apa pun.
- **Tombol/chip yang sedang dipilih kini lebih jelas terbaca, terutama di
  Mode Gelap.** Sebelumnya teks pada pilihan aktif (mis. tombol jenis
  pembayaran di layar Bayar) tampak buram/samar. Sekaligus, notifikasi
  "berhasil" kini berwarna hijau dan "gagal" berwarna merah (sebelumnya
  keduanya senada warna aksen), jadi lebih cepat dikenali sekilas.

## 8 Juli 2026

### ✨ Fitur Baru
- **Checkbox "Kembalian" di struk — cegah kembalian diberikan dua kali.**
  Untuk nota yang barangnya diambil belakangan, sekarang ada centang kecil
  di samping baris "Kembalian" di struk. Setelah kembalian benar-benar
  diserahkan ke pembeli, tinggal dicentang — jadi kasir lain (atau kasir
  yang sama, lupa) tidak salah kasih kembalian lagi saat pembeli kembali
  mengambil barang.
- **Kolom cari di layar Kasir kini melebar otomatis saat disentuh.**
  Sebelumnya kolom cari selalu berdesakan dengan tombol-tombol di
  sampingnya (scan, antrian, riwayat, dll). Sekarang kolom cari tampil
  ringkas dulu, lalu melebar mulus menutupi tombol-tombol itu begitu
  disentuh — ada tombol "x" untuk menghapus teks atau mengecilkan lagi
  kolomnya. Tap di luar kolom (mis. di daftar produk kosong) otomatis
  mengecilkan kolom lagi tanpa menghapus kata yang sudah diketik. Tap
  tombol "+" atau badan produk hasil pencarian TIDAK ikut mengecilkan
  kolom — jadi bisa tap beberapa barang hasil cari berturut-turut tanpa
  kolom cari tiba-tiba menutup.
- **Tombol Bayar Nanti kini terpisah, tidak lagi campur dengan Metode
  Pembayaran.** Di layar Bayar, sekarang ada 2 tombol besar di bagian
  bawah: **"Bayar [jumlah]"** (hijau, untuk pembayaran tunai/QRIS/dll seperti
  biasa) dan **"Bayar Nanti"** (merah, langsung mencatat sebagai hutang).
  Lebih jelas dan tidak perlu mencari-cari chip "Bayar Nanti" di antara
  metode pembayaran lain.
- **Harga Lain di pengaturan produk.** Selain harga grosir, sekarang produk
  bisa punya harga alternatif dengan nama bebas — misal harga jual "Sedap
  Goreng" normalnya Rp 2.850, tapi bisa ditambah harga bernama "Harga Toko
  A" senilai Rp 3.000. Saat di kasir, tap produk lalu pilih harga itu
  langsung dari daftar chip harga, tidak perlu ketik manual. Atur lewat
  Kelola Produk → pilih produk → "Tambah Harga Lain".

### 🧪 Eksperimental
- **Katalog Pesanan: dropdown varian tidak lagi otomatis tertutup.**
  Sebelumnya, tiap kali menambah jumlah varian (mis. pilih rasa), daftar
  variannya langsung tertutup lagi — merepotkan kalau mau pilih beberapa
  rasa sekaligus. Sekarang tetap terbuka sampai pelanggan sendiri yang
  menutupnya dengan tap nama produknya.
- **Katalog Pesanan: ada tombol ganti tampilan terang/gelap** (ikon
  matahari/bulan di pojok kanan atas), pilihan tersimpan otomatis untuk
  kunjungan berikutnya. Teks Total di halaman ini juga diperbesar supaya
  lebih mudah dibaca.
- **Katalog Pesanan kini bisa langsung ditempel ke keranjang kasir.**
  Sebelumnya, kasir harus membaca pesanan WhatsApp dari pelanggan satu-satu
  dan menginputnya manual. Sekarang, cukup salin (copy) teks pesanan yang
  dikirim pelanggan, buka layar Kasir, tekan tombol baru "Tempel Pesanan" di
  pojok atas, lalu tempel — barang, jumlah, dan nama pelanggan otomatis
  terisi ke keranjang. Harga yang dipakai selalu harga TERBARU di aplikasi
  (bukan harga lama yang mungkin tertulis di pesanan), dan barang yang sudah
  dihapus/dinonaktifkan sejak katalog dikirim akan ditandai jelas sebagai
  "tidak ditemukan" tanpa mengganggu barang lain yang valid.

---

## 7 Juli 2026

### 🛠️ Perbaikan yang Terasa
- **Retur di toko dengan lebih dari satu rekening bank kini berfungsi.**
  Sebelumnya, kalau Metode Pembayaran berisi dua metode sejenis (mis. bank
  "BRI" dan "BCA"), membuka layar retur untuk nota lunas bisa error dan
  retur tidak bisa dilakukan. Sekarang pilihan "Kembalikan via" menampilkan
  tiap rekening dengan benar.
- **Kembalian dari pelunasan hutang tidak hilang lagi** — di semua tempat:
  "Tambah Bayar" di struk, tombol "Lunasi" di Riwayat Transaksi, dan
  "Tambah Bayar" di Laporan. Sebelumnya, kalau pelanggan melunasi hutang
  dengan uang lebih (mis. hutang Rp 95.000 dibayar Rp 100.000), catatan
  "Kembali Rp 5.000" bisa lenyap atau tidak tercatat sama sekali. Kolom
  nominal di dialog Laporan kini juga otomatis berpemisah ribuan.
- **Import ulang file CSV kini memperbarui harga, bukan menggandakan
  produk.** Sebelumnya, mengimport file yang sama dua kali membuat seluruh
  katalog dobel dan barcode "pindah" ke produk duplikat sehingga hasil scan
  jadi kacau. Sekarang produk yang sudah ada dikenali (lewat barcode, kode,
  atau nama+satuan) dan hanya harganya yang diperbarui.
- **Data tahun yang sudah ditutup buku tidak bisa muncul dobel lagi.**
  Sebelumnya, sinkronisasi dari HP kasir setelah owner melakukan tutup buku
  bisa memasukkan kembali transaksi tahun lama ke data utama (dobel dengan
  arsip). Sekarang data tahun terarsip otomatis disaring saat sync.
- **Pesan yang jelas saat jam HP berbeda.** Kalau sinkronisasi gagal karena
  jam kedua HP selisih lebih dari 5 menit, kini muncul petunjuk berbahasa
  Indonesia untuk menyamakan tanggal & jam — bukan pesan teknis.
- **Poin pelanggan kembali utuh saat retur dibatalkan.** Sebelumnya poin
  yang dipotong saat retur hilang permanen walau retur-nya di-void.
- **Aplikasi terbuka lebih cepat** di toko dengan riwayat transaksi besar —
  pekerjaan perapihan data dipindah ke belakang layar setelah layar tampil.
- **Pengaturan Izin Kasir dirapikan**: dua izin yang fiturnya memang belum
  ada di aplikasi ("Input Pengeluaran" & "Input Pembelian") disembunyikan
  agar tidak membingungkan.

### 🧪 Eksperimental
- **Katalog Pesanan (baru, tahap awal).** Di Pengaturan → Eksperimental,
  owner sekarang bisa membuat & membagikan satu file "Katalog Pesanan" ke
  pelanggan lewat WhatsApp. Pelanggan buka file itu di HP-nya (tanpa perlu
  internet), pilih sendiri barang & jumlahnya — termasuk varian (mis.
  pilihan rasa) — lalu tekan "Kirim via WhatsApp" untuk mengirim pesanan
  yang sudah rapi terformat. **Catatan penting**: file ini TIDAK otomatis
  ter-update — tiap kali harga berubah, perlu dibuat & dikirim ulang. (Lihat
  pembaruan 8 Juli: kasir kini bisa menempel pesanan ini langsung ke
  keranjang, tidak perlu input manual lagi.)

---

## 6 Juli 2026

### 🛠️ Perbaikan yang Terasa
- **Riwayat Transaksi kini langsung menampilkan transaksi terbaru** setiap
  dibuka — sebelumnya kadang perlu tekan tombol refresh dulu supaya
  transaksi yang baru saja dibuat kelihatan.
- **Restore backup ke HP/toko baru kini benar-benar bisa.** Sebelumnya,
  memulihkan file backup (`.berkahpos`) di HP lain atau setelah install ulang
  aplikasi SELALU gagal dengan pesan "password salah atau data rusak" —
  walau passwordnya sudah benar. Sekarang file backup bisa dibuka di
  device/toko manapun asal passwordnya benar, sesuai yang sudah dijanjikan.
- **Restore backup di HP yang sama kini benar-benar mengubah data.**
  Sebelumnya aplikasi bilang "Data berhasil di-restore" tapi layar (mis.
  daftar pelanggan) tidak ikut ter-update — data lama masih tampil sampai
  aplikasi ditutup & dibuka ulang manual. Sekarang layar langsung
  menampilkan data hasil restore. Untuk beberapa layar (Ringkasan, grup
  produk) aplikasi tetap menyarankan tutup-buka ulang agar 100% konsisten.

### ✨ Fitur Baru
- **Sisa hutang & kembalian kini langsung terlihat di Riwayat Transaksi.**
  Sebelumnya harus buka struk dulu baru sadar nota belum lunas penuh atau ada
  kembalian yang menggantung (paling sering bikin bingung di nota gabungan
  beberapa pelanggan). Sekarang baris riwayat langsung menampilkan
  **"Sisa Rp ..."** (merah) kalau nota belum lunas penuh, atau
  **"Kembali Rp ..."** (hijau) kalau lunas dan ada kembalian. Nota dengan
  uang pas tidak menampilkan tambahan apa pun.

---

## 5 Juli 2026

### 🛠️ Perbaikan yang Terasa
- **Struk tidak lagi bisa terpotong di layar sempit.** Kalau nama perangkat
  kasir cukup panjang, baris "Kasir: ..." di struk berpotensi mendorong
  tanggal transaksi sampai terpotong dari layar. Sekarang otomatis
  menyingkat (...) agar tanggal tetap selalu terlihat penuh. Baris ringkasan
  retur untuk nota belum lunas juga diperbaiki dengan cara serupa.

### ✨ Fitur Baru
- **Retur untuk nota belum lunas (hutang) kini lebih masuk akal.** Kalau
  pelanggan mengembalikan barang dari nota yang **belum dibayar sama sekali
  atau baru dibayar sebagian**, aplikasi sekarang langsung **mengurangi
  hutangnya** — bukan lagi berpura-pura ada uang tunai yang harus
  dikembalikan. Barang yang diretur langsung hilang dari nota itu, totalnya
  otomatis berkurang. Untuk nota yang **sudah lunas**, cara retur tetap sama
  seperti sebelumnya (nota retur terpisah + uang kembali beneran), karena
  uangnya memang sudah diterima toko.

---

## 2 Juli 2026

### 🛠️ Perbaikan yang Terasa
- **Aplikasi tetap cepat dibuka meski data sudah menumpuk tahunan.** Ditemukan
  lewat uji beban: pembukaan aplikasi bisa melambat drastis (hingga hang) saat
  jumlah transaksi membesar. Sudah diperbaiki — startup tetap ringan bahkan di
  atas satu juta transaksi.
- **QRIS kini tampil sebagai kode QR sungguhan** di layar pembayaran — pembeli
  bisa langsung scan. Sebelumnya hanya muncul tulisan kode mentah yang tidak
  bisa discan.
- **Struk lebih akurat untuk produk bervarian** — bila induk (mis. Pop Ice)
  dijual bersama varian rasanya sekaligus, baris induk di struk aplikasi
  sempat tampil kosong tanpa nominal. Sekarang jumlah & harganya tampil benar.
- **Total pesanan ditahan kini akurat** — kartu "Pesanan Ditahan" sempat
  menghitung varian dua kali sehingga totalnya kelihatan lebih besar.
- Berbagai penguatan di balik layar: stok aman saat tutup buku tahunan, data
  pegawai ikut ter-backup, dan sinkronisasi antar perangkat lebih andal untuk
  cicilan / tambah belanjaan pada nota lama.

---

## 1 Juli 2026

### ✨ Fitur Baru
- **Katalog Harga** — Buat daftar harga produk dan bagikan sebagai gambar ke
  pelanggan (mis. lewat WhatsApp). Pilih produk seperti biasa di kasir, lalu
  bagikan. Daftar otomatis dikelompokkan per kategori, lengkap dengan nama toko,
  tanggal, dan kontak. Katalog bisa disimpan dan **diedit kembali** kapan saja.
- **Animasi konfirmasi scan** — Saat memindai barcode dengan kamera (mode Scan
  Berulang), garis merah pemindai berkedip hijau sesaat sebagai tanda produk
  berhasil masuk keranjang.
- **Cara baru buka keranjang** — Cukup geser (swipe) bar total belanja ke atas
  untuk melihat isi keranjang. Tombol "Lihat" dan "Bayar" di bar disederhanakan.
- **Ekspor laporan lebih lengkap** — Ekspor (PDF & Excel) kini mengikuti tab yang
  dibuka (Ringkasan / Produk / Pelanggan / Transaksi), dan PDF menyertakan grafik
  (donut & batang) persis seperti tampilan di aplikasi.

### 🛠️ Perbaikan yang Terasa
- Ekspor PDF laporan yang sebelumnya gagal/macet pada data besar kini lancar.
- Tulisan pada grafik di PDF yang tadinya sulit terbaca kini jelas.

---

## 27–28 Juni 2026

### ✨ Fitur Baru
- **Cari produk lewat SKU** dan **edit item langsung dari dalam keranjang**.
- **Getar (haptik)** saat scan barcode berhasil; scanner eksternal otomatis
  membuka keranjang setelah scan.
- **Sinkronisasi harga satu arah** antar toko dengan persetujuan per kategori.
- **Izin stok minus** untuk asisten/kasir dapat diatur.

---

## 25–26 Juni 2026

### ✨ Fitur Baru
- **Ekspor CSV produk** dan **katalog sinkron harga** dari halaman Pengaturan.
- Tambahan **5 satuan** baru: Ons, Rek, Paket, Box, Karton.

---

## 19–21 Juni 2026

### ✨ Fitur Baru
- **Tambah belanjaan** ke transaksi yang sudah ada dengan alur bayar selisih.
- **Sinkronisasi via QR code** untuk data dan harga antar perangkat.
- **Senter (torch)** dan panduan bidik pada scanner kamera.
- Pelanggan & pegawai bisa dipilih langsung di bar keranjang; tahan pesanan
  jadi lebih praktis.

---

## 16–18 Juni 2026

### ✨ Fitur Baru
- **Poin loyalitas** dengan aturan yang bisa dikonfigurasi dan poin yang bisa
  diedit.
- **Penyesuaian stok manual** dari halaman detail produk.
- **Pengaturan ukuran teks global** + penyesuaian otomatis mengikuti layar.
- **Pencatatan pegawai per nota** yang tampil di struk.
- **Sinkronisasi harga antar toko** lewat WiFi langsung maupun CSV.

### 🛠️ Perbaikan yang Terasa
- Warna navigasi sistem Android mengikuti mode gelap/terang.

---

## 13–15 Juni 2026

### ✨ Fitur Baru
- **Struk dapat dikustomisasi** — header (WhatsApp/Telegram/teks bebas), ukuran
  kertas 58/80mm, dan pilihan tampil/sembunyi tiap bagian.
- **Gabung beberapa nota** satu pelanggan menjadi satu cetakan, dengan timeline
  pembayaran.
- **Varian produk bersarang** dan **manajemen grup produk**.
- **Bagikan struk sebagai gambar** ke aplikasi lain.
- Edit nama pembeli langsung di layar struk.

---

## 11–12 Juni 2026 — Rilis Awal

### ✨ Fondasi Aplikasi
- **Kasir** — katalog grid/list, pencarian, keranjang, pesanan ditahan, dan
  metode pembayaran lengkap (tunai, transfer, QRIS, e-wallet, tempo/kasbon)
  termasuk pembayaran sebagian & kembalian.
- **Barcode scanner ganda** — kamera dan scanner hardware eksternal.
- **Multi-satuan & harga berjenjang** (harga grosir per kuantitas/grup pelanggan).
- **Pelanggan** dengan poin loyalitas & pelacakan hutang.
- **Cetak struk thermal Bluetooth** (ESC/POS).
- **Laporan** 4 tab (Ringkasan, Produk, Pelanggan, Transaksi) dengan grafik dan
  pemilih rentang tanggal; pembatalan transaksi (void) dengan reversal stok.
- **Multi-perangkat** owner + kasir via sinkronisasi WiFi LAN, izin kasir per
  peran, backup/restore, dan impor CSV.
- **Tutup buku tahunan** dengan arsip read-only.
