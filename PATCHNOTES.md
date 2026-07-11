# Catatan Pembaruan (Patch Notes)

Ringkasan perubahan yang **dirasakan pengguna**, ditulis dalam bahasa sederhana.
Untuk catatan teknis lengkap per-commit, lihat [CHANGELOG.md](CHANGELOG.md).

> Yang dicantumkan di sini: fitur baru & perbaikan yang benar-benar terasa saat
> memakai aplikasi. Perbaikan internal/teknis tidak dicantumkan.

---

## 11 Juli 2026

### ✨ Fitur Baru
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
