# Catatan Pembaruan (Patch Notes)

Ringkasan perubahan yang **dirasakan pengguna**, ditulis dalam bahasa sederhana.
Untuk catatan teknis lengkap per-commit, lihat [CHANGELOG.md](CHANGELOG.md).

> Yang dicantumkan di sini: fitur baru & perbaikan yang benar-benar terasa saat
> memakai aplikasi. Perbaikan internal/teknis tidak dicantumkan.

---

## 1 September 2026

### ✨ Fitur Baru
- **Bisa membagikan pratinjau keranjang ke pelanggan sebelum checkout**
  — kalau pelanggan minta lihat rincian & estimasi total dulu (mis.
  lewat WhatsApp), tap ikon share baru di header keranjang ("Bagikan
  Pratinjau"). Struknya sengaja dibuat beda tampilan dari struk asli
  (banner "PRATINJAU KERANJANG", label "Estimasi Total") supaya tidak
  tertukar dengan struk resmi. Bisa juga sertakan QR QRIS dengan
  nominal yang otomatis mengikuti estimasi total saat ini, kalau
  pelanggan mau langsung transfer.

## 31 Agustus 2026

### ✨ Fitur Baru
- **Batas jumlah (kuota) antrian pre-order per produk** — misalnya
  kiriman normal LPG dari pangkalan 70 tabung: setel angkanya lewat
  tombol kuota di dashboard Laci Meja → Pre-order, lalu pilih chip
  produknya. Daftar antrian akan diberi garis "Batas kiriman normal"
  di posisi yang pas, plus nomor antrian tiap pelanggan, jadi jelas
  siapa saja yang bisa dilayani dari kiriman berikutnya. Garisnya
  otomatis bergeser sendiri kalau ada pesanan yang dipenuhi duluan —
  tidak perlu disetel ulang.
- **Filter produk di daftar pre-order** — kalau ada lebih dari satu
  produk yang sedang diantri, bisa dipilih satu per satu.
- **Semua catatan Laci Meja sekarang bisa diedit** (titip/ketinggalan,
  pinjaman, maupun pre-order) — lewat ikon pensil di kartunya pada
  struk in-app. Jumlah, nama, telepon, jaminan, dan catatan bisa
  dibetulkan tanpa harus "dipenuhi lalu dibuat ulang" seperti dulu,
  jadi riwayatnya tetap jujur. Kartu yang pernah diedit menampilkan
  keterangan "Terakhir diedit" beserta waktunya. Jumlah tidak bisa
  diturunkan di bawah yang sudah terlanjur diambil/dikembalikan.
- **Kartu Pinjaman bisa disematkan (pin) ke atas daftar** — untuk
  pinjaman yang perlu terus terlihat, tanpa terpengaruh urutan waktu.
- **Pelanggan terdaftar kini dibedakan tampilannya dari nama biasa** —
  di bar keranjang kasir, kartu Laci Meja, dan header nota: ikon orang
  terisi + warna aksen untuk pelanggan yang punya data tersimpan,
  ikon garis + warna netral untuk nama yang hanya diketik saat itu.
- **Bisa menandai barang di nota yang sudah tersimpan sebagai pre-order**
  — untuk kasus lupa input pre-order saat checkout (mis. stok LPG
  ternyata kosong, baru sadar setelah nota lunas/tempo tersimpan).
  Tap baris barangnya di struk in-app, pilih "Jadikan Pre-order", isi
  jumlah (dan jumlah jaminan bila produknya pakai jaminan) — nota itu
  sendiri tidak berubah, cuma dicatat sebagai pre-order yang bisa
  dikelola dari dashboard Laci Meja.

### ✨ Fitur Baru
- **Pelanggan yang sudah terdaftar kini ditandai dengan warna
  terracotta juga di NAMA-nya** — sebelumnya cuma ikon kecil, sekarang
  namanya sendiri ikut berwarna di cart bar kasir, kartu Laci Meja,
  dan header struk in-app, jadi lebih mudah dikenali sekilas.
- **Chip jaminan di dashboard Laci Meja → Pre-order kini bisa diganti
  produk yang ditampilkan**, dengan tampilan dropdown yang dirancang
  ulang lebih rapi — tinggal tap chip-nya untuk memilih, tanpa perlu
  buka tooltip berulang kali tiap mau lihat produk lain.

### 🔧 Perbaikan
- **Jumlah tempo (Sisa) yang sebelumnya bisa hilang dari struk cetak/
  bagikan saat nota juga punya kembalian** — kalau nota sempat dibayar
  lebih (dapat kembalian) lalu ditambah belanjaan lagi hingga jadi
  tempo, struk sekarang tetap menampilkan Kembali DAN Sisa
  bersamaan, tidak lagi saling menghilangkan.
- **Angka "Produk"/"Jaminan" di dashboard Laci Meja → Pre-order kini
  tampil sbg chip kecil** (label biasa + angka tebal, gaya kartu lama
  yang disukai tetap dipertahankan) berdampingan dgn tombol "Kuota" —
  jauh lebih ringkas dari kartu besar sebelumnya, tanpa kehilangan
  tampilan yang jelas dibaca. Rincian jaminan per produk tetap bisa
  dilihat lewat ikon info di sebelahnya.
- **Tampilan filter produk & kartu statistik di dashboard Laci Meja
  → Pre-order dirapikan** — filter dan kartu "Total produk"/"Total
  jaminan" sekarang jadi satu panel yang rapi, tombol "Kuota" diberi
  label yang jelas.
- **Kuota antrian pre-order sekarang benar-benar tersinkron ke semua
  perangkat** (owner ↔ kasir) — sebelumnya kuota yang disetel di satu
  perangkat tidak pernah sampai ke perangkat lain, termasuk perubahan
  pada beberapa pengaturan toko lain yang sudah lama ada (mis. nama
  toko) yang diubah setelah pernah tersinkron sekali.
- **Garis batas kuota pre-order sekarang ikut mempertimbangkan
  pesanan yang sudah diambil sebagian** — sebelumnya pesanan yang
  sudah diserahkan sebagian (mis. 4 dari 5 tabung) tetap dianggap
  utuh saat menghitung kuota, jadi antrian di bawahnya seolah tidak
  pernah "naik" walau barangnya sudah nyaris habis diserahkan.
- **Jumlah barang & jaminan di kartu pre-order kini menampilkan
  SISA yang belum diserahkan**, bukan angka pesanan awal yang jadi
  basi begitu ada pengambilan sebagian — kartu statistik "Total
  produk"/"Total jaminan" ikut disesuaikan.
- **Garis batas kuota diganti jadi putus-putus abu-abu**
  (sebelumnya solid & berwarna kuning/oranye), dan label "Batas
  kiriman normal" disingkat jadi "Batas kiriman".
- **Garis batas kuota pre-order kini muncul juga saat cuma satu produk
  yang sedang diantri** (mis. hanya LPG) — sebelumnya garisnya tidak
  pernah tampil di kondisi itu walau kuotanya sudah disetel.
- **Retur barang yang sama di lebih dari satu baris nota** (mis. beli
  lagi lewat "Tambah Belanjaan") sekarang bisa diretur penuh dalam satu
  kali buka menu Retur — sebelumnya jumlah yang bisa diretur sekaligus
  bisa lebih sedikit dari yang seharusnya.

## 30 Agustus 2026

### ✨ Fitur Baru
- **Riwayat Transaksi sekarang bisa difilter berdasarkan metode
  pembayaran** (Tunai/Transfer Bank/QRIS/E-Wallet/Tempo) — chip baru
  di samping filter status & tanggal yang sudah ada.

### 🔧 Perbaikan
- **Chart "Penjualan Harian" di Laporan tidak lagi tumpuk labelnya**
  untuk rentang tanggal panjang (mis. sebulan penuh) — diganti jadi
  chart garis, sama seperti chart "Tren penjualan" di detail produk.
  Sekalian, kedua chart ini sekarang menampilkan nominal PUNCAK
  langsung di layar (garis putus-putus + angkanya) tanpa perlu tap
  atau geser dulu.
- **Rincian jam di chart "Penjualan Per Jam" (Ringkasan) sekarang dibuka
  dengan sekali TAP** — sebelumnya harus tekan-tahan dan otomatis hilang
  begitu jari dilepas. Sekarang tap satu batang untuk melihat detailnya,
  tetap tampil sampai kamu tap batang lain, tap area lain di layar, atau
  scroll.
- **Metode pembayaran di struk (cetak, share, & tampilan in-app) sekarang
  menampilkan nama spesifik yang kamu atur sendiri** (mis. "GoPay", "BCA")
  — bukan cuma kategori umum "E-Wallet"/"Transfer Bank". Nota lama (sebelum
  pembaruan ini) tetap tampil dengan label umum seperti biasa.
- **Opsi baru di Pengaturan > Printer Bluetooth: "Putuskan koneksi otomatis
  setelah cetak"** — berguna kalau printer kamu tidak mendukung 2 perangkat
  sekaligus, atau sering gagal cetak setelah Bluetooth dimatikan-nyalakan.
  Default tetap seperti sebelumnya (printer tetap tersambung setelah cetak)
  supaya yang biasa cetak cepat tanpa reconnect tidak terganggu.

## 29 Agustus 2026

### 🔧 Perbaikan
- **Statistik detail produk kini akurat untuk produk dengan lebih dari
  satu satuan** — sebelumnya angka "Terjual" & grafik tren di layar
  detail produk (Laporan > Produk > ketuk produk) menjumlah semua
  satuan mentah-mentah (mis. penjualan 2 dus + 20 pcs tampil sbg
  "22", padahal 1 dus isinya puluhan pcs). Sekarang totalnya
  dikonversi ke satuan dasar produk (mis. "100 pcs"), plus ada
  keterangan tambahan kalau ada satuan lain yang ikut terjual
  (mis. "dari itu: 3 dus").

## 23 Agustus 2026

### ✨ Tampilan
- **Tombol +/- di kasir & keranjang disederhanakan lagi** — ikon "+"
  sedikit dikecilkan saat belum ditambahkan, dan lingkaran solid di
  belakang angka/tombol saat sudah di keranjang dihilangkan (cuma angka
  & ikonnya saja yang tampil, warnanya tetap hijau/merah seperti
  biasa). Area yang bisa disentuh tidak berubah sama sekali.
- **Warna ikon avatar produk di halaman kasir dilembutkan** — dulu
  warnanya pekat/solid, sekarang latar jadi warna muda dengan huruf
  tetap berwarna solid, senada dengan gaya chip lain di app.
- **Warna ikon avatar produk kini juga menyesuaikan mode gelap** —
  sebelumnya latarnya tetap terang mencolok walau app dipakai dalam
  mode gelap, sekarang latarnya jadi lebih redup & menyatu dengan tema.

### 🎉 Fitur Baru
- **Catatan barang titip/ketinggalan (di luar nota) kini bisa ditulis
  beberapa baris** — tekan Enter untuk membuat baris baru, cocok untuk
  mencatat lebih dari satu barang sekaligus.

- **Kartu Pre-order kini menampilkan status "Tempo"/"Lunas"** — pre-order
  yang uang mukanya (DP) belum dibayar ditandai "Tempo" (merah), yang
  DP-nya sudah dibayar ditandai "Lunas" (hijau), menempel setelah
  keterangan jaminan/nama barangnya. Keterangan "sudah bayar" yang lama
  dihapus karena fungsinya sudah tergantikan status ini.
- **Pre-order kini bisa dirujuk dari transaksi lain** — kalau seorang
  pelanggan punya pre-order yang masih terbuka, lalu belanja lagi di
  nota yang berbeda, sekarang ada tautan yang bisa diklik (di cart bar
  saat nama pelanggan diketik, maupun di struk untuk barang yang sama)
  untuk langsung membuka nota asli tempat pre-order itu dicatat.

### 🗑️ Fitur Dihapus
- **Tombol batal (X) di kartu Pre-order Laci Meja dihapus** — kini
  hanya tombol "Penuhi" yang tersedia di kartu tersebut.
- **Barang di Laci Meja bisa diambil sebagian** — misal pelanggan
  menitipkan 5 tabung LPG lalu hanya mengambil 3, sisanya (2) tetap
  tercatat menggantung, lengkap dengan bar progres "Diambil 3 dari 5".
  Berlaku juga untuk pinjaman barang dan pre-order.
- **Riwayat pengambilan di tiap nota** — buka notanya, sekarang terlihat
  kapan barang dicatat dan kapan saja diambil/dikembalikan/dipenuhi,
  beserta jumlahnya. Pre-order yang sebelumnya tidak muncul sama sekali
  di nota kini punya bagiannya sendiri.
- **Layar Riwayat Laci Meja** — ikon jam di pojok kanan atas Laci Meja
  menampilkan seluruh catatan pengambilan ketiga kategori jadi satu,
  urut dari yang terbaru dan dikelompokkan per hari.

### 🔧 Perbaikan
- **Laci Meja: nama pelanggan sekarang ikut notanya** — dulu kalau nota
  diubah dari pembeli umum ke nama pelanggan (atau sebaliknya), entri
  di Laci Meja tetap menampilkan nama lama. Sekarang namanya selalu
  mengikuti nota, termasuk untuk entri lama yang terlanjur salah.
- **Dropdown saran nama pelanggan di struk sekarang bisa discroll** —
  saat mengetik nama pelanggan di struk in-app, daftar saran yang
  muncul sebelumnya tidak bisa digulir sama sekali, jadi saran yang
  jatuh di luar layar (terutama saat keyboard terbuka) tidak terlihat.
  Sekarang bisa digulir seperti biasa, dan daftar sarannya juga tidak
  lagi berhenti di 5 nama teratas — pelanggan yang cocok tapi ada di
  urutan lebih bawah kini ikut muncul, tinggal digulir.

### ✨ Tampilan (lanjutan)
- **Kartu Laci Meja ditata ulang** — nama pelanggan naik ke paling atas
  (paling besar & tebal), nama barang + jumlah di baris kedua, dan
  **waktu pencatatan kini ditampilkan** di baris ketiga (tanggal & jam,
  format sama dengan Riwayat Pembayaran). Berlaku untuk ketiga kategori:
  titip/ketinggalan, pinjaman, dan pre-order.

### 🗑️ Fitur Dihapus
- **Import dari Griyo POS** (Pengaturan > Eksperimental) dihapus.
- **Cek Duplikat Data** (Pengaturan) dihapus.

## 22 Agustus 2026

### ✨ Fitur Baru
- **Logo QRIS resmi di struk** — muncul di atas kode QR pelunasan, baik
  saat struk dibagikan sebagai gambar maupun dicetak ke printer thermal.
- **Header keranjang (nama pelanggan/pegawai/Tahan/Bayar) tampil lebih
  rapi** — empat bagian dalam satu baris dengan sudut atas membulat halus
  & pemisah tipis antar bagian, tombol Bayar tetap paling menonjol karena
  itu aksi utama.

### 🐛 Perbaikan
- **Struk dengan QR pelunasan (nota tempo/kurang bayar dgn QRIS aktif)
  gagal tercetak sama sekali di printer thermal** — printer terhubung &
  terlihat memproses, tapi kertas tidak pernah keluar. Sudah diperbaiki.
- **Logo QRIS di struk cetak terlalu besar** — sekarang disusutkan
  seukuran kode QR di bawahnya.
- **Total pendapatan & angka lain di layar Ringkasan/Laporan tidak
  bertambah setelah sinkronisasi dari perangkat lain** — data sudah benar
  di database, tapi layarnya perlu ditarik-refresh manual dulu untuk
  terlihat. Sekarang otomatis terupdate begitu sinkronisasi selesai.

### 🐛 Perbaikan
- **Tampilan tombol "+" saat idle disederhanakan lagi** — garis
  lingkaran putus-putus sebelumnya dirasa masih terlalu tegas, sekarang
  cukup satu garis tipis di samping tombol.

## 20 Agustus 2026

### ✨ Fitur Baru
- **QR pelunasan di nota tempo** — saat membagikan atau mencetak struk nota
  yang masih tempo/kurang bayar dan toko sudah mengaktifkan QRIS, kini ada
  opsi untuk menampilkan QR pelunasan langsung di struk (nominalnya sisa
  tagihan, bukan total nota). Ada juga pilihan QR Dinamis (nominal sudah
  terisi otomatis) atau Statis (pelanggan isi sendiri), plus keterangan
  "Mohon konfirmasi setelah membayar." Pilihan ini diingat aplikasi untuk
  struk-struk berikutnya.
- **Mode terang/gelap di layar aktivasi kode serial** — sekarang bisa
  diganti langsung dari layar pertama saat mengaktifkan aplikasi, tidak
  perlu menunggu masuk ke Pengaturan.
- **Tampilan tombol "+" di kartu produk kasir dirapikan** — sebelum
  produk ditambahkan ke keranjang, tombol tampil lebih ringan (ring
  putus-putus, tanpa warna solid/bayangan) supaya tidak terlalu "ramai"
  saat melihat banyak produk sekaligus. Begitu produk masuk keranjang,
  tombol berubah jadi warna solid seperti biasa.

### 🐛 Perbaikan
- **Sheet kalkulator bayar nota tempo (mode QRIS statis) & sheet Bagikan
  Struk (saat QR pelunasan dinyalakan) sekarang bisa ditutup dengan
  swipe ke bawah** — sebelumnya macet karena isinya lebih panjang dari
  layar.
- **Tombol +/- diperbesar** — di baris keranjang, kartu/daftar produk, dan
  baris varian di layar Kasir — supaya lebih mudah dan tidak salah pencet.
- **Jarak tombol Bayar/Uang Pas di kalkulator bayar nota tempo dirapikan**
  agar tidak bergeser-geser saat ganti metode pembayaran.
- **Label tombol ganti mode QR di kalkulator bayar nota tempo diperbaiki**
  — sekarang menunjukkan mode yang akan dituju, bukan mode yang sedang aktif.

## 18 Agustus 2026

### 🐛 Perbaikan
- **Rincian "Metode Pembayaran" di Laporan sekarang menghitung Transfer
  Bank dengan benar**: sebelumnya transaksi Transfer Bank selalu tercatat
  Rp 0 di rincian tersebut (uangnya diam-diam masuk ke "Lainnya"), dan di
  struk/riwayat/cetak thermal metodenya tampil sebagai tulisan "bank"
  mentah, bukan "Transfer". Total Omzet/Laba tidak pernah salah — cuma
  rincian per-metode pembayaran yang keliru.

### 🆕 Fitur baru
- **Bayar hutang/tempo sekarang pakai kalkulator yang sama seperti kasir**:
  tombol "Bayar" di struk (juga di Riwayat Transaksi, Daftar Transaksi, dan
  "Lunasi Hutang" di Laporan) kini membuka panel kalkulator yang bisa
  digeser ke bawah untuk ditutup — bukan lagi kotak dialog kecil. Metode
  pembayaran bisa dipilih langsung di dalamnya.
- **Nomor rekening & QRIS ikut tampil saat melunasi hutang**: pilih metode
  Transfer Bank atau E-Wallet, nomornya langsung muncul di sebelah tombol
  metode lengkap dengan tombol salin. Pilih QRIS, QR-nya tampil di panel
  yang sama — pelanggan tinggal scan, tidak perlu lagi buka layar lain.
- **QRIS saat melunasi hutang bisa dikunci nominalnya**: awalnya tampil QR
  biasa beserta kalkulator (karena jumlah cicilan biasanya perlu diketik
  dulu). Setelah jumlahnya diketik, geser tombol ke "Nominal" — QR berganti
  membawa jumlah itu, jadi pelanggan tidak perlu mengetik sendiri. Salah
  geser pun aman: angka yang sudah diketik tidak hilang.

- **QR QRIS langsung membawa nominal belanja**: saat metode QRIS dipilih
  di layar Bayar, QR yang tampil sudah berisi jumlah yang harus dibayar —
  pelanggan tinggal scan lalu langsung ke layar konfirmasi, tidak perlu
  mengetik nominal sendiri (salah ketik jumlah jadi hilang). Nominalnya
  diambil dari QRIS statis toko Anda sendiri yang diisi di Pengaturan →
  Metode Pembayaran, jadi dana tetap masuk ke rekening yang sama.
  Pembayaran tetap dikonfirmasi manual oleh kasir seperti biasa.
- **Tombol geser Statis / Nominal di kartu QR**: ada di pojok kanan atas
  kartu QR pada layar Bayar. Geser ke "Statis" kalau ingin menampilkan QR
  polos (pelanggan mengetik sendiri jumlahnya), geser ke "Nominal" untuk
  QR yang sudah terkunci jumlahnya. Pilihan ini tersimpan — tidak perlu
  digeser ulang tiap transaksi, dan otomatis ikut ke HP kasir lain.
- **Bayar QRIS mode "Nominal" jadi satu ketukan saja**: karena jumlahnya
  sudah terkunci di QR dan pelanggan tidak bisa mengubahnya, kasir tidak
  perlu lagi melewati kalkulator — cukup tekan "Bayar" dan nota langsung
  tercatat lunas. Kalau QR-nya mode "Statis", kalkulator tetap muncul
  seperti biasa (jumlah yang dibayar pelanggan bisa saja tidak penuh).
- **Bayar non-tunai sekarang bisa pakai kalkulator, termasuk bayar kurang**:
  dulu kalau pilih metode selain Tunai (Transfer Bank/E-Wallet/QRIS) di
  layar Bayar, jumlahnya otomatis dianggap lunas penuh — tidak ada
  kalkulator sama sekali. Sekarang tombol "Bayar" membuka kalkulator yang
  sama persis seperti Tunai untuk semua metode, jadi kasir bisa mengetik
  nominal yang benar-benar diterima — kalau kurang, otomatis tercatat
  sebagai hutang (kurang bayar), sama seperti Tunai. Di kalkulator ada
  penanda kecil "Metode: ..." supaya kasir tetap tahu sedang input nominal
  untuk metode yang mana.
- **No. rekening/akun tampil otomatis saat Bayar**: kalau metode
  pembayaran Transfer Bank atau E-Wallet sudah diisi nomornya di
  Pengaturan → Metode Pembayaran, sekarang nomornya langsung tampil di
  layar Bayar begitu metode itu dipilih — lengkap tombol salin. Tidak
  perlu buka Pengaturan lagi atau hafal manual saat melayani pelanggan.

## 14 Agustus 2026

### 🆕 Fitur baru
- **Tombol "Tahan Pesanan" di keranjang**: sekarang ada tombol Tahan
  (ikon jeda) langsung di bagian atas keranjang, di sebelah kiri tombol
  "Tempel Pesanan" — jadi kasir tidak perlu tutup dulu keranjangnya
  untuk menahan pesanan. Kalau pelanggan sudah dipilih, langsung
  ditahan pakai nama pelanggan itu; kalau belum, muncul kotak cari
  pelanggan yang SAMA persis dengan yang di cart bar — bisa cari
  pelanggan terdaftar (langsung kelihatan kalau dia punya hutang) atau
  ketik nama/penanda bebas (misal "Meja 3").

### 🔧 Perbaikan
- **QR Transfer Transaksi lebih gampang di-scan**: gambar QR di sheet
  "Transfer Transaksi"/"Kirim ke Owner/Asisten" sekarang cuma berisi
  kode intinya saja — jadi tidak sepadat dan tidak segelap dulu, lebih
  gampang dibaca kamera scanner. Daftar barang lengkap tetap ada kok,
  cuma dipindah ke tombol "Salin Teks Pesanan" dan "Share Pesanan" —
  jadi kalau mau kirim manual lewat WhatsApp/Telegram, teksnya tetap
  enak dibaca lengkap dengan nama barang & totalnya.

---

## 13 Agustus 2026

### 🆕 Fitur baru
- **Riwayat Pembayaran lebih detail** (di struk in-app, saat lihat
  kembali sebuah nota): setiap kali ada **retur atau edit barang**,
  sekarang tampil rincian barang apa saja yang diretur/diedit — nama
  barang, jumlah, harga satuan, dan totalnya — tanpa perlu menghitung
  ulang manual. Untuk **nota tempo/kurang bayar**, tiap kali kasir
  menerima sebagian pembayaran, langsung tampil juga baris "Sisa" di
  bawahnya (contoh: total belanja Rp 193.000, dibayar Tunai Rp 192.000,
  Sisa Rp 1.000) — persis seperti baris "Kembalian" yang sudah ada,
  tapi tanpa perlu dicentang karena sisa tempo tidak akan dipakai
  ulang. Kembalian atau sisa yang muncul TEPAT pada momen retur/edit
  itu sendiri juga langsung terlihat di situ. Fitur ini murni untuk
  membantu kasir & audit — struk yang dibagikan (share/cetak) tidak
  berubah.

---

## 11 Agustus 2026

### 🆕 Fitur baru
- **Penerimaan Barang**: tempel daftar barang yang datang (satu baris
  "jumlah satuan nama", misalnya "5 pcs Indomie Goreng") dan stok
  langsung bertambah. Baris pemisah tanggal otomatis diabaikan. Barang
  yang namanya tidak persis sama tinggal dipilih sekali dari daftar
  (ada kotak pencarian), lalu **diingat** — penerimaan berikutnya tidak
  akan menanyakan barang yang sama lagi, dan ingatan itu ikut tersalin
  ke perangkat lain saat sinkron. Bisa dibuka dari layar Cek Stok.
- **Statistik per produk & per pelanggan**: baris di Laporan → tab
  Produk dan tab Pelanggan sekarang **bisa diketuk** untuk melihat
  rinciannya — kapan saja terjual, tren harian, siapa pembelinya, dan
  untuk pelanggan: barang apa yang rutin dia beli + riwayat notanya.
  Semuanya bisa disaring per rentang tanggal. Statistik pelanggan juga
  bisa dibuka langsung dari halaman detail pelanggan. Grafik tren
  penjualan produk sekarang berupa **garis interaktif** — sentuh atau
  geser di sepanjang garis untuk melihat tanggal & jumlahnya, dan tetap
  rapi walau rentang tanggalnya panjang (mis. setahun penuh).
- **Laporan Arus Kas** (tab baru di Laporan): uang yang benar-benar
  masuk & keluar pada rentang itu — nota tempo yang belum dibayar
  tidak ikut dihitung, dan pelunasan hutang nota lama dihitung di
  tanggal uangnya benar-benar diterima. Dipisah tunai vs non-tunai,
  lengkap dengan tren harian.
- **Nilai rupiah selisih di riwayat Stock Opname** — sebelumnya cuma
  menampilkan jumlah barang; sekarang terlihat berapa rupiah modal yang
  susut (atau lebih) dari tiap sesi opname.

### 🔧 Perbaikan
- **Retur/hapus barang yang melebihi sisa hutang sekarang memunculkan
  kembalian** — sebelumnya, kalau pelanggan punya hutang tempo lalu
  meretur barang senilai lebih dari sisa hutangnya, kelebihan yang jadi
  haknya tidak muncul di mana pun sehingga kasir tidak tahu ada uang
  yang harus dikembalikan. Sekarang tampil sebagai kembalian biasa,
  lengkap dengan centang "sudah diserahkan".
- **Pengaturan toko ikut tersalin ke perangkat lain saat sinkron** —
  aturan poin loyalti, kebijakan stok minus, nama/alamat/nomor toko di
  struk, catatan struk, daftar metode pembayaran, dan daftar pegawai.
  Sebelumnya semua itu hanya berlaku di perangkat pemilik; akibatnya
  belanja bernilai sama bisa mendapat poin berbeda tergantung perangkat
  mana yang melayani, dan struk dari perangkat berbeda bisa
  mencantumkan alamat/nomor yang sudah tidak berlaku.

## 9 Agustus 2026

### 🔧 Perbaikan
- **Tombol debug sementara di "Tempel Pesanan" (ikon kutu) sudah
  dicabut** — dipasang untuk investigasi bug pegawai tidak bisa tempel
  pesanan, bug-nya sudah tidak lagi terjadi jadi tombolnya tidak
  diperlukan lagi.
- **Angka "Sisa" di Riwayat Transaksi sekarang selalu sama dengan
  "Sisa Tagihan" di struk** — sebelumnya, untuk nota yang kembaliannya
  dipakai ulang sebagai pembayaran, Riwayat Transaksi bisa menampilkan
  angka yang salah (bahkan minus), padahal struknya sendiri sudah
  benar. Tombol "Lunasi" juga ikut dibetulkan supaya jumlah yang
  tercatat sebagai pembayaran selalu akurat.

## 8 Agustus 2026

### 🆕 Fitur baru
- **QR/teks transfer keranjang antar-perangkat sekarang menampilkan
  daftar barang & totalnya**, bukan cuma kode acak — jadi sebelum
  scan, penerima (atau siapa pun yang lihat pesannya di WhatsApp)
  bisa langsung baca sekilas isi pesanannya.

### 🔧 Perbaikan
- **Penghapusan pengeluaran sekarang ikut tersinkron ke perangkat
  lain** — sebelumnya, pengeluaran yang dihapus di satu perangkat
  bisa tetap muncul di perangkat lain yang sudah menerimanya lebih
  dulu, bikin laba bersih beda antar perangkat.
- **Dialog terima data sync**: kategori "Stok" sekarang otomatis
  ikut tercentang & tidak bisa dilepas selama kategori "Transaksi"
  dipilih — mencegah penjualan tercatat tanpa stoknya ikut berkurang.
- **"Sync Ulang Penuh" sekarang benar-benar penuh** — dulu cuma
  mereset satu arah (data yang dikirim), sekarang mereset kedua arah
  sekaligus. Membantu kalau jam salah satu perangkat pernah salah
  setel dan sinkron jadi macet.
- **Pelunasan/cicilan/tambahan belanja pada nota yang sudah pernah
  disinkron sekarang selalu sampai ke pemilik toko.** Sebelumnya,
  kalau nota itu headernya sudah lebih dulu tersinkron, pelunasan atau
  penambahan barang belakangan padanya bisa gagal terkirim sama
  sekali dan otomatis ditolak dengan pesan "tidak ada data baru" —
  padahal ada.
- **Nota tempo yang belum lunas tidak lagi bisa "hilang" dari Laporan
  → Buku Hutang.** Sebelumnya, kalau pelanggan yang sama punya nota
  lain yang pernah kelebihan bayar (kembalian dari nota itu dipakai
  ulang untuk belanja tambahan), nota tempo-nya yang genuinely belum
  lunas bisa hilang sama sekali dari daftar Buku Hutang — padahal
  tetap muncul normal di riwayat transaksi. Sekarang perhitungannya
  benar, nota tempo selalu tampil.
- **Poin loyalti pelanggan tidak lagi bisa "hilang" setelah sinkron
  antar-perangkat.** Sebelumnya, kalau pegawai/kasir mencatat poin
  baru untuk pelanggan, lalu perangkat itu sinkron dengan pemilik
  toko, poin barunya kadang bisa tertimpa balik ke angka lama.
  Sekarang poin selalu dihitung ulang dari riwayat lengkap
  (transaksi masuk/keluar poin) setelah sinkron, jadi tidak akan
  pernah salah atau hilang.
- **Saldo stok tidak lagi bisa berubah salah setelah Tutup Buku** —
  kalau sebuah barang punya riwayat stok sebelum DAN sesudah periode
  yang baru diarsipkan (bukan cuma di periode yang diarsipkan itu
  sendiri), sebelumnya saldo barang tersebut bisa jadi salah begitu
  sinkron dengan perangkat lain pertama kali dilakukan pasca Tutup
  Buku. Sekarang saldo dijamin tetap benar.
- **Data yang dikirim kasir/pegawai untuk disetujui pemilik toko tidak
  lagi bisa hilang tanpa jejak** kalau perangkat itu sinkron dua kali
  berturut-turut sebelum sempat disetujui (misal tap tombol sync 2x,
  atau sinkron otomatis kepicu lagi). Sebelumnya, sinkron kedua bisa
  menimpa & menghapus permanen data dari sinkron pertama yang belum
  sempat ditinjau pemilik toko — sekarang data digabung, tidak ada yang
  hilang.

## 6 Agustus 2026

### 🆕 Fitur baru
- **Letak checkbox verifikasi di baris keranjang sekarang bisa diatur
  sendiri** — tombol pengaturan (ikon gerigi) baru di samping ikon
  "Tempel Pesanan" di keranjang, dengan 4 pilihan posisi: depan qty
  (default), belakang tombol +/-, kiri tombol minus, atau di sebelah
  nama barang.
- **Opsi konfirmasi sebelum tombol minus mengurangi qty** — di dialog
  pengaturan yang sama, cegah qty berkurang tanpa sengaja kalau jari
  tergelincir menekan tombol minus. Kalau aktif, tap pertama tombol
  minus membuat baris item bergetar sebagai peringatan (belum
  mengurangi apa pun) — tap berikutnya (selama jari belum pindah ke
  tombol lain) baru benar-benar mengurangi qty, boleh ditekan
  berkali-kali beruntun seperti stepper biasa. Mati secara default,
  bisa diaktifkan sendiri.

### 🔧 Perbaikan
- **Pre-order/titip/pinjaman yang sudah selesai (Dipenuhi/Dibatalkan/
  Diambil/Dikembalikan) tidak lagi terus-menerus muncul sebagai usulan
  baru** di layar Sync pemilik toko — sebelumnya bisa terus diusulkan
  ulang walau sudah pernah disetujui.
- **Transfer keranjang lewat scan QR antar HP sekarang membawa semua
  detail** — harga yang sudah diubah manual, satuan Harga Lain, dan
  centang verifikasi item sekarang ikut terbawa ke penerima. Sebelumnya
  detail ini hilang dan harga dihitung ulang dari awal di HP penerima.
  **Kecuali** untuk pegawai tanpa izin "Terima Pembayaran" — harga dari
  device mereka tetap dihitung ulang otomatis di HP penerima (bukan
  dipercaya mentah-mentah), supaya owner tidak menerima harga yang belum
  divalidasi.
- **Usulan Laci Meja (Titip/Ketinggalan/Pinjaman/Pre-order) dari kasir
  ke pemilik toko tidak lagi gagal total** saat transaksi terkaitnya
  belum sempat tersinkron ke perangkat pemilik — sekarang baris itu
  ditunda otomatis dan akan muncul lagi begitu transaksinya sampai.
- **Checkbox verifikasi di baris keranjang kembali ke sisi kiri** (sempat
  dipindah ke kanan di update sebelumnya).

## 5 Agustus 2026

### 🆕 Fitur baru
- **Katalog HTML (pesan sendiri via WhatsApp): keranjang pelanggan bisa
  hapus barang langsung** — tiap baris ada ikon tempat sampah sendiri
  (dulu cuma bisa turunkan jumlah sampai 0), lengkap dengan konfirmasi
  sebelum benar-benar terhapus. Tombol "Kosongkan" juga diperjelas jadi
  "Kosongkan Keranjang" dengan ikon merah di pojok kanan atas.
- **Nomor serial device sekarang disamarkan (spoiler)** di halaman
  Lisensi & Serial — tersembunyi di balik pola titik-titik sampai
  diketuk, mencegah orang lewat membaca sidik jari device sekilas.
- **Panduan & Tips ditambah 6 bab baru**: Printer Bluetooth, Backup &
  Restore + Alihkan Owner, Poin Loyalitas, Retur & Edit Transaksi
  Lunas, Tutup Kasir vs Tutup Buku, dan Katalog Pesanan.

### 🔧 Perbaikan
- **Ikon di halaman Tentang Aplikasi diganti gambar resolusi lebih
  tinggi** — tidak lagi terlihat patah-patah/pecah di HP layar tajam.
- Garis tipis yang sempat muncul di atas isi panduan saat dibuka
  (Panduan & Tips) sudah dihilangkan.
- Seksi "Segera Hadir" di halaman Lisensi & Serial dihapus (belum ada
  isinya, cuma tempat kosong).

## 4 Agustus 2026

### 🆕 Fitur baru
- **Halaman baru "Tentang Aplikasi"** (Pengaturan → Lainnya → Tentang
  Aplikasi) — nomor versi, dan tombol "?" untuk buka "Panduan & Tips":
  daftar panduan yang bisa dicari (mis. ketik "izin" atau "tempel
  pesanan"), tiap panduan disertai tips fitur yang mungkin belum
  disadari (mis. tempel pesanan otomatis masuk ke keranjang aktif).
- **"Info Lisensi & Serial"** (nomor serial dalam bentuk QR — bisa
  langsung discan developer, tanggal diaktifkan, tanggal berlaku
  sampai) sekarang dibuka dari halaman "Tentang Aplikasi" di atas. QR
  serial juga tampil di layar aktivasi device baru.
- **Keranjang sekarang ingat posisi scroll terakhir** — kalau sedang
  mencentang barang di keranjang yang panjang lalu tidak sengaja kepencet
  item (kembali ke layar kasir), begitu buka keranjang lagi posisinya
  langsung di tempat yang sama seperti sebelum ditutup, tidak perlu
  scroll ulang dari atas.

### 🔧 Perbaikan
- **Layar review usulan dari kasir/asisten sekarang tampilkan SEMUA yang
  berubah, bukan cuma harga** — dulu kalau yang diubah bukan harga
  (misalnya satuan produk, isi kemasan, barcode, nama produk), layarnya
  tetap bilang "Tidak ada perubahan harga" padahal usulannya memang sah,
  bikin bingung/nyaris ke-skip padahal ada perubahan nyata yang perlu
  ditinjau.

## 3 Agustus 2026

### 🆕 Fitur baru
- **Item keranjang yang sudah dicentang kini dapat highlight lembut** —
  warna latar tipis di baris itemnya, jadi sekilas kelihatan barang mana
  yang sudah diverifikasi/dicek saat serah-terima, tanpa perlu lihat
  kotak centangnya satu-satu.
- **"Tempel Pesanan" sekarang bisa langsung dari keranjang** — ada ikon
  baru di pojok atas keranjang, kapan saja (walau keranjang masih kosong).
  Berguna kalau ada pesanan tambahan dari pelanggan (lewat Katalog HTML)
  atau pegawai yang mau menambah pesanan, sebelum keranjang di-checkout.
  Tombol yang sama juga sekarang muncul di layar "Tambah Belanjaan" (nota
  yang sudah dibayar tempo/lunas) — dulu disembunyikan di sana.
- **Scan QR "Transfer" sekarang bisa langsung nambah ke keranjang yang
  sedang dibuka** — kalau kasir sedang melayani transaksi (keranjang
  sudah ada isinya) lalu scan QR pesanan tambahan dari pegawai lain,
  barangnya langsung masuk ke keranjang yang sama, tidak perlu buka
  antrian terpisah dulu.
- **Usulan pelanggan dari kasir/asisten sekarang bisa disetujui owner** —
  kalau kasir/asisten (bukan owner) menambah atau mengubah data
  pelanggan, perubahan itu sekarang terkirim sebagai "usulan" saat sync
  ke owner (mirip usulan harga produk yang sudah ada), muncul di layar
  Sync untuk ditinjau & disetujui. Sebelumnya perubahan pelanggan dari
  device kasir/asisten tidak pernah sampai ke perangkat owner sama
  sekali.

### 🔧 Perbaikan
- **Tombol di layar kirim QR keranjang diganti** — dulu ada tombol "Sudah
  Dikirim, Kosongkan Keranjang" persis di atas tombol "Tutup", jadi rawan
  salah pencet dan keranjang yang sebenarnya BELUM terkirim ikut terhapus.
  Sekarang tombol itu diganti "Share Pesanan" (kirim teks pesanan lewat
  WhatsApp/dll). Mengosongkan keranjang tetap bisa lewat ikon tempat sampah
  di pojok atas keranjang seperti biasa.

## 1 Agustus 2026 (lanjutan)

### 🆕 Fitur baru
- **Varian bisa "ikut harga satuan dasar" otomatis** — saklar baru di
  dialog Tambah/Edit Varian. Kalau dinyalakan, harga varian otomatis ikut
  berubah tiap kali harga satuan dasar produk induk diubah (dikalikan isi
  per satuan), jadi tidak perlu update manual satu-satu.
- **Harga varian sekarang bisa diketik langsung saat jual** — di modal
  tambah item kasir, begitu varian ditambah jumlahnya, muncul kotak harga
  yang bisa diedit manual, plus pilihan Harga Lain langsung tampil sebagai
  kotak kecil (tidak perlu buka menu pop-up lagi).

## 1 Agustus 2026

### 🆕 Fitur baru
- **Varian sekarang bisa punya satuan sendiri + isi per satuan** — di dialog
  Tambah/Edit Varian ada pilihan "Jenis Satuan" (mis. Renteng, Dus) dan
  "Isi per Satuan". Contoh: varian dijual per Renteng yang berisi 10 pcs —
  stoknya tetap dihitung dalam satuan dasar, tapi ditampilkan & dijual per
  Renteng. Kalau isinya dibiarkan 1, varian bekerja persis seperti sebelumnya.

### ✨ Penyesuaian tampilan
- **Nominal per barang di keranjang pindah ke bawah baris satuan & harga**
  (mis. di bawah "Karung · Rp 65.000") — dulu sebaris dengan tombol +/−,
  sehingga tombolnya ikut bergeser tiap kali diketuk (nominalnya melebar).
  Sekarang tombolnya diam di tempat.
- **Kotak centang di keranjang pindah ke kanan** (agak renggang dari tombol
  −), tepat di kiri stepper.
- **Ikon tab Ringkasan** diganti jadi ikon kertas & pensil.

### 🛠️ Perbaikan
- **Centang barang hilang saat "Tambah Belanjaan"** — barang yang sudah
  dicentang di keranjang muncul tanpa centang di struk saat ditambahkan ke
  nota yang sudah lunas/tempo. Sekarang ikut tercentang, dan centang barang
  lama di nota itu tidak hilang.

## 31 Juli 2026

### 🆕 Fitur baru
- **Stok varian sekarang bisa disesuaikan** — ikon stok baru di tiap
  baris varian (Edit Produk) membuka dialog "Sesuaikan Stok", sama
  seperti satuan produk utama. Sebelumnya stok varian cuma bisa dilihat,
  tidak bisa diubah dari mana pun.
- **Harga Lain varian sekarang bisa dipakai saat jual** — saat kasir
  menambah varian yang punya Harga Lain ke keranjang, muncul ikon kecil
  di baris varian untuk memilih harga mana yang dipakai. Sebelumnya
  Harga Lain varian cuma bisa disimpan, tidak pernah benar-benar
  terpakai saat transaksi.
- **Varian sekarang bisa punya Harga Lain sendiri** — dikelola langsung
  dari dialog Tambah/Edit Varian di Edit Produk, tombol "Tambah Harga
  Lain" sama seperti di form produk utama.
- **Status stok varian sekarang terlihat** — di Edit Produk (daftar
  Varian) maupun saat kasir menambah varian ke keranjang, sekarang tampil
  "Stok N", "Habis", atau "Non-stok" per varian. Sebelumnya stok varian
  memang tercatat tapi tidak pernah ditampilkan di mana pun.

### 🛠️ Perbaikan
- **Usulan Titip/Ketinggalan dari kasir kadang gagal diterapkan owner**
  ("Gagal menerapkan usulan: FOREIGN KEY constraint failed") — terjadi kalau
  barang itu ditautkan ke pelanggan baru yang belum sempat dikenal di HP
  owner. Sekarang selalu berhasil diterapkan.
- **Jumlah varian sekarang bisa diketik langsung** (bukan cuma tombol +/−)
  — sama seperti Titip/Ketinggalan, berguna untuk varian produk timbang.

## 30 Juli 2026

### 🛠️ Perbaikan
- **Retur barang sekarang bisa jumlah desimal** — sebelumnya kalau mau retur
  produk timbang (mis. minyak kelapa 4.5kg) cuma bisa pakai tombol +/− yang
  loncat kelipatan 1, jadi mustahil retur sebagian angka desimal (mis. 2.5
  dari beli 4.5). Sekarang jumlahnya bisa diketik langsung, nominal
  pengembaliannya otomatis menyesuaikan proporsional.

## 29 Juli 2026

### 🆕 Fitur baru
- **Catat Titip/Ketinggalan sekarang bisa untuk barang yang TIDAK dibeli di
  toko ini** — kadang ada barang pelanggan yang bukan dari toko (tapi
  tertinggal), atau barang yang memang sengaja dititipkan. Sekarang ada
  kolom "Atau barang lain (di luar nota)" utk diketik bebas, di samping
  centang produk yang tetap jadi cara utama. Barang yang diketik bebas ini
  tampil sbg bagian terpisah di struk, sama seperti Pinjaman Barang.
- **Pilihan Titip/Ketinggalan dipindah ke atas** — sebelumnya di bawah
  daftar produk, jadi kalau produk di nota banyak, staf harus scroll dulu.
  Sekarang langsung terlihat begitu dialog dibuka.

## 27 Juli 2026

### 🛠️ Perbaikan
- **Bar keranjang dirombak biar tidak "goyang" lagi** — dulu nama pelanggan
  panjang bikin tombol Tahan/Bayar pindah baris & posisinya berubah-ubah.
  Sekarang porsi tiap tombol tetap, dan nama yang kepanjangan ditampilkan
  sebagai **teks berjalan** (bergerak kiri-kanan beberapa kali lalu diam),
  jadi nama tetap kebaca utuh tanpa mengubah tata letak.
- **Pengingat di bar keranjang jadi lebih jelas** — catatan Laci Meja
  pelanggan tampil satu baris per jenis (barang ketinggalan, pinjaman,
  pre-order), dan baris pre-order menyebut langsung produk apa, berapa,
  serta berapa jaminan yang dititip.
- **Pengingat hutang sekarang juga muncul di bar keranjang** (di bawah
  nominal Total): total hutang & di berapa nota, jadi ketahuan sebelum
  transaksi baru diselesaikan.
- **Catat Pinjaman Barang kembali ketik bebas** — supaya wadah kosong
  (galon/tabung) yang memang bukan barang di nota tetap bisa dicatat.
  Daftar pinjaman muncul sebagai bagian tersendiri di struk dalam aplikasi.
- **Keterangan jaminan tidak lagi hilang dari nota** setelah pre-order-nya
  ditandai terpenuhi.
- **Menu tekan-tahan tab "Kasir" dirombak tampilannya** — sekarang muncul
  tepat di atas tab (bukan di samping), hanya tampil ikon Kasir/Laci Meja
  (tanpa teks), sudutnya rounded, waktu tekan-tahan yang dibutuhkan untuk
  membukanya dipercepat, dan sekarang muncul/hilangnya dengan animasi
  halus (bukan langsung nongol/hilang begitu saja).
- **Dashboard Laci Meja — barang Titip/Ketinggalan dari nota yang sama
  sekarang dikelompokkan jadi satu kartu**, tidak lagi tampil sebagai
  baris-baris terpisah yang membingungkan. Tiap barang juga menampilkan
  jumlah & satuannya. Tombol "Sudah Diambil" juga disederhanakan jadi
  tombol kecil "Ambil".
- **Tab Ringkasan di Laporan tidak lagi terasa "renggang"** — jarak antar
  kartu ringkasan (Omzet, Transaksi, dll) dirapikan, dan tab "Ringkasan"
  sekarang menempel rapi di kiri (sebelumnya ada jarak kosong yang tidak
  perlu).
- **Dashboard Laci Meja — Pre-order dari nota yang sama sekarang
  dikelompokkan jadi satu kartu** (nama pelanggan tampil sekali di atas,
  daftar barang & jumlah jaminan di bawahnya), dan **Pinjaman Barang
  dikelompokkan per pelanggan** — jadi satu pelanggan yang pinjam
  beberapa kali di nota berbeda tetap kelihatan jadi satu daftar.
- **Struk in-app sekarang menandai barang yang sedang dipinjamkan** —
  label "Pinjaman" di samping nama barang, sebagai bukti kalau ada
  yang perlu dicek ulang.
- **Statistik jaminan di tab Pre-order sekarang lebih detail** — istilah
  "wadah" diganti "jaminan", dan di bawah angka total jaminan sekarang
  ada rincian per produk (mis. "LPG: 20 jaminan"), dengan nama produk &
  angkanya ditebalkan biar cepat dibaca.
- **Baris rincian pre-order juga ditebalkan** — nama produk & jumlahnya
  di kartu Pre-order sekarang bold, sisanya (jaminan, status bayar)
  tetap teks biasa.
- **Keterangan "Titip [jumlah]" jaminan pre-order di struk sekarang
  otomatis hilang setelah pre-order-nya dipenuhi** di dashboard Laci
  Meja — sama seperti keterangan barang titip/ketinggalan, tidak lagi
  menempel selamanya di struk.
- **Perbaikan: nama pelanggan panjang di bar keranjang tidak lagi
  terpotong permanen** di HP dengan pengaturan ukuran font besar —
  sekarang teks berjalan (marquee) tetap aktif sesuai ukuran font yang
  sedang dipakai, tidak lagi mengira teksnya muat padahal sebenarnya
  kepotong.
- **Teks nama pelanggan yang berjalan (marquee) sekarang berulang terus**
  — sebelumnya berhenti selamanya setelah beberapa putaran, jadi kalau
  layar dilihat beberapa detik kemudian nama malah kelihatan seperti
  kepotong lagi. Sekarang istirahat sebentar lalu jalan lagi otomatis.
- **Nama pelanggan panjang di bar keranjang akhirnya benar-benar berjalan**
  — sebelumnya nama seperti "Buk Khotimah" cuma menampilkan "Buk" dan
  sisanya kosong (kata kedua hilang, bukan bergerak). Sekarang nama
  panjang selalu ditampilkan sebagai teks berjalan seperti seharusnya.
- **Catat Titip/Ketinggalan sekarang bisa untuk SEBAGIAN barang saja** —
  kalau yang ketinggalan/dititip cuma sebagian dari jumlah yang dibeli
  (mis. beli 5, ketinggalan 2), sekarang ada tombol +/- untuk mengatur
  jumlahnya, tidak lagi selalu dianggap semua barang yang tertinggal.
- **Jumlah di Catat Titip/Ketinggalan sekarang bisa desimal** — untuk
  produk timbang (mis. beras/minyak dijual per kg), angkanya bisa
  diketik langsung (mis. "4.5"), tidak lagi terbatas kelipatan bulat.
- **Keterangan Titip/Ketinggalan/jaminan di struk in-app didekatkan ke
  nama barang** — sekarang posisinya persis seperti tanda "Habis" di
  daftar produk kasir, tidak berjarak lagi.
- **Struk yang dibagikan (gambar)**: baris jumlah barang & harga per
  barang tidak lagi tercetak tebal — hanya nama produk yang tetap tebal,
  jadi lebih mudah dibaca.
- **Transaksi tidak bisa dibayar setelah pesanan dipindah bolak-balik
  lewat QR** (mis. owner → asisten → owner) — muncul pesan error dan
  kasir mentok padahal uang sudah diterima. Sekarang pembayaran selalu
  bisa diselesaikan; nomor notanya yang menyesuaikan otomatis.
- **Nama pelanggan panjang di bar keranjang tidak lagi menutupi tombol
  "Bayar"** — barisnya turun ke bawah kalau tidak muat, dan tombol
  "Bayar"-nya sekarang selalu tetap di kanan walau baris di sebelahnya
  melipat jadi 2 baris.
- **Keterangan pengingat Laci Meja sekarang menyebut jenis barang yang
  benar** — barang yang tercatat "ketinggalan" tidak lagi ikut tertulis
  "dititip" di pengingat modal checkout/bar keranjang.

### ✨ Fitur Baru
- **"Laci Meja" — fitur baru untuk catatan operasional harian toko.**
  Tekan & tahan tab "Kasir" di menu bawah (mirip Telegram) untuk membuka
  dashboard barunya. Ada 3 kategori:
  - **Titip/Ketinggalan** — catat barang yang lupa dibawa pembeli atau
    sengaja dititip. Dicatat langsung dari layar Struk lewat tombol baru
    "+ Catat" — tinggal centang barang mana di nota itu yang titip/
    ketinggalan, bisa lebih dari satu sekaligus.
  - **Pinjaman Barang** — catat wadah/deposit (galon, tabung gas, dll)
    yang harus kembali secara fisik ke toko, bisa dicatat kembali
    sebagian (mis. pinjam 3, baru kembali 2).
  - **Pre-order** — kini punya **kotak pencarian** (cari nama pelanggan
    atau nama produk) dan **ringkasan angka**: total produk yang dipesan
    dan total jaminan yang dititip, ditampilkan terpisah & ikut menyesuaikan
    hasil pencarian.
  - **Pre-order** — catat pesanan untuk produk yang stoknya sedang habis
    (termasuk antrian tabung LPG). **Diperbarui**: sekarang dicatat
    langsung lewat modal tambah barang di Kasir — begitu produk ditandai
    "Habis", muncul pertanyaan "Pre-order?" (Ya/Tidak), lalu "DP?" (bayar
    sekarang atau nanti), dan kalau produknya butuh jaminan fisik (mis.
    tukar tabung gas), muncul kolom jumlah jaminan yang dititip. Karena
    langsung nyambung ke keranjang, pesanan pre-order otomatis tercatat
    di nota yang sama — memudahkan pelacakan & tap-untuk-lihat-nota di
    dashboard Laci Meja.
  - Badge angka di ikon Kasir menampilkan total catatan yang masih aktif
    di ketiga kategori, tanpa perlu ditahan dulu.
  - Untuk produk model tukar-wadah (mis. LPG), ada toggle baru "Butuh
    Jaminan Fisik saat Antri" di form Edit Produk — kalau diaktifkan,
    pencatatan antrian mewajibkan jumlah wadah yang dititip diisi.
  - Kalau ada catatan Laci Meja yang dibuat pegawai/asisten (bukan
    owner), owner bisa meninjau & menyetujuinya dulu di layar Sinkron
    WiFi (kartu "Usulan Laci Meja") sebelum masuk ke data toko.
  - Ketuk salah satu catatan di dashboard Laci Meja untuk langsung
    membuka struk nota terkait (mirip cara buka nota dari Buku Hutang).
  - Nama pelanggan otomatis terbawa dari nota, jadi langsung terlihat di
    kartu Laci Meja tanpa perlu diketik ulang (ditandai warna terracotta
    supaya mudah dibedakan).
  - Barang yang dititip/ketinggalan diberi penanda langsung di struk
    dalam aplikasi, mirip penanda "Habis" pada daftar produk.
  - Saat menerima pembayaran, muncul pengingat kalau pelanggan itu masih
    punya barang dititip, pinjaman, atau pre-order yang belum selesai —
    warnanya sengaja dibedakan dari pengingat hutang.

## 26 Juli 2026

### ✨ Fitur Baru
- **Produk utama sekarang bisa diset non-stok**, tidak cuma varian. Ada
  toggle "Lacak stok" baru di tiap satuan pada form Edit Produk — matikan
  kalau satuan itu tidak perlu dihitung stoknya (mis. produk jasa).
- **Menu baru "Jeda Pelacakan Stok"** (Pengaturan > Manajemen Data) —
  set SEMUA produk yang masih dilacak stoknya jadi non-stok sementara
  sekaligus, tanpa perlu edit satu-satu. Bisa dikembalikan kapan saja lewat
  toggle yang sama, dan akan kembali PERSIS seperti semula (produk yang
  memang sudah non-stok sejak awal, mis. jasa, tidak ikut berubah).

### 🛠️ Perbaikan
- **Nominal kembalian di struk (dalam aplikasi) sekarang lebih menonjol
  (tebal)** — supaya kasir tidak salah lihat berapa uang kembali yang
  harus diserahkan sekarang, beda dari riwayat pembayaran di bawahnya yang
  cuma catatan.
- **Pembayaran yang dibatalkan tidak lagi ikut tercetak/dibagikan di
  struk.** Dulu kalau ada pembayaran yang salah lalu dibatalkan (mis. salah
  ketik nominal), baris itu tetap ikut tercetak di struk kertas & struk
  gambar (share) seolah pembayaran sungguhan — bisa terlihat seperti
  pelanggan bayar berkali-kali. Sekarang pembayaran yang sudah dibatalkan
  hanya tampil di riwayat pembayaran dalam aplikasi, tidak lagi ikut ke
  struk yang dicetak atau dibagikan.

## 25 Juli 2026

### ✨ Fitur Baru
- **Menu baru "Cek Duplikat Data"** (Pengaturan > Diagnostik, khusus owner) —
  memeriksa apakah ada produk yang barcode/harga-nya ke-dobel (misalnya 2
  barcode "Primer" sekaligus), yang bisa terjadi kalau HP pernah restore
  backup dari HP lain yang datanya sempat kurang rapi. Kalau ketemu, tinggal
  ketuk produknya untuk membuka Edit Produk lalu simpan ulang — otomatis
  rapi jadi satu.
- **Nama produk panjang di keranjang tidak lagi terpotong** — sekarang
  boleh tampil sampai 2 baris.
- **Stock Opname bisa dihitung pakai satuan yang lebih nyaman** — produk
  yang punya beberapa satuan (misalnya Pcs/Dus) sekarang bisa dihitung
  langsung dalam satuan besarnya (misalnya "10 dus"), otomatis dikonversi
  ke satuan dasar. Produk dengan satu satuan saja tidak berubah sama
  sekali.
- **Cek Stok: tentukan sendiri jumlah & satuan yang mau diorder.** Setiap
  produk yang dicentang kini punya baris `[−] [jumlah] [+] [satuan]` —
  jumlahnya mulai dari 1, bisa dinaikkan/diturunkan, atau **diketuk untuk
  mengetik angkanya langsung**. Satuannya bisa dipilih dari satuan milik
  produk itu (Pcs/Dus) maupun dari daftar satuan umum, jadi produk
  bersatuan tunggal pun tetap bisa diorder dalam satuan lain. Teks yang
  dikirim ke supplier jadi berbentuk "10 Dus Indomie".
- **Filter Semua / Dicentang / Belum di Cek Stok.** Berlaku bersamaan dengan
  filter kategori, jadi bisa misalnya melihat hanya produk Sembako yang belum
  dicentang. Judul panel juga menunjukkan berapa produk yang akan ikut
  terkirim ke supplier.
- **Kecualikan kategori tertentu dari teks Order Restock.** Kalau ada
  kategori yang memang dipesan lewat cara lain (misalnya LPG), sekarang bisa
  ditandai "dikecualikan" — produknya tetap boleh dicentang & tampil di
  daftar seperti biasa, cuma tidak ikut ditulis ke teks yang dikirim ke
  supplier. Chip ini muncul di atas kotak teks kalau tokonya punya 2
  kategori atau lebih.
- **Tampilan baris jumlah order di Cek Stok dirombak** — kotak −/+/satuan
  sekarang jadi satu jalur menyatu yang serasi dengan tampilan field lain
  di aplikasi, dan angkanya pakai gaya angka yang sama dengan nominal Rupiah
  di seluruh aplikasi.
- **Warna kartu produk tercentang di Cek Stok tidak lagi ikut warna
  kritis/aman stoknya** — dulu produk berstok kritis yang dicentang jadi
  merah tebal (dua arti berbeda numpuk jadi satu warna, membingungkan).
  Sekarang produk tercentang selalu warna oranye netral, dan warna
  kritis/menipis/aman tetap cuma di angka badge stoknya.
- **Teks Order Restock sekarang bisa diedit langsung, dua arah.** Anda bisa
  mengetik/menempel langsung di kotak teksnya; centang, jumlah, dan satuan
  di daftar atas ikut menyesuaikan. Menghapus satu baris juga otomatis
  membatalkan centang produknya.
- **Kasir: "Harga Lain" langsung tampil sebagai pilihan, tidak perlu buka
  menu dulu.** Sebelumnya harga grosir/harga alternatif satuan disembunyikan
  di balik satu tombol "Harga lain (N)" — sekarang setiap opsi (harga
  dasar, tier grosir, harga alternatif) langsung tampil sebagai kotak
  pilihan sendiri-sendiri, sebaris dengan "Pilih satuan" di atasnya. Tinggal
  ketuk salah satu, tanpa buka apa pun dulu.

### 🛠️ Perbaikan
- **Barcode/tier grosir/Harga Lain yang diganti owner sekarang benar-benar
  hilang dari HP kasir/asisten setelah sinkronisasi.** Dulu kalau owner
  mengedit barcode (atau tier harga grosir/Harga Lain) sebuah produk,
  nilai LAMA-nya tetap tersimpan di HP kasir/asisten setelah sync —
  barcode lama masih bisa di-scan, dan hasilnya bisa keliru. Sekarang
  nilai lama ikut terhapus begitu ada penggantinya di owner.
- **Memilih "Harga Lain" tidak lagi mematikan tanda satuan yang aktif.**
  Sebelumnya begitu Anda memilih harga alternatif/grosir, kotak satuan yang
  sedang dipakai jadi terlihat "tidak terpilih" — padahal satuannya sendiri
  tidak berubah. Sekarang keduanya independen: kotak satuan tetap menyala
  sesuai satuan yang aktif, kotak harga menyala sesuai harga yang dipakai.
- **Tanda "stok habis" yang diubah owner sekarang benar-benar tersinkron ke
  HP kasir/asisten** — sebelumnya bisa tersangkut & tidak pernah sampai ke
  perangkat lain, terutama untuk produk yang sudah lama tidak diedit.
- **Kategori produk (buat/ganti nama/hapus/urutkan) sekarang benar-benar
  tersinkron ke HP kasir/asisten** — sebelumnya kategori baru yang dibuat
  owner tidak pernah sampai ke perangkat lain, meski produk yang
  ditugaskan ke kategori itu sudah tersinkron duluan.
- **Sinkronisasi data 2 device yang kebetulan berbagi alamat IP (mis.
  hotspot HP) sekarang tidak lagi saling menimpa** — sebelumnya kalau 2
  HP berbeda tersambung dari IP yang sama, sinkronisasi salah satu bisa
  hilang tergantikan yang lain.
- **Stok kadang tampil tidak update ke angka terbaru** kalau ada 2
  perubahan stok yang terjadi sangat berdekatan (misalnya atur stok awal
  langsung disusul stock opname) — sekarang selalu menampilkan angka
  hasil perubahan terakhir.
- **Salah angka saat "Sesuaikan" stok sudah tidak mungkin lagi** — dulu
  angka stok lama di kotak "Stok baru" tidak tersorot, jadi kalau langsung
  diketik tanpa menghapusnya dulu, angkanya menempel di belakang yang lama
  (stok 5, ketik 12, tersimpan jadi 512). Sekarang angka lamanya otomatis
  tersorot, jadi mengetik langsung menggantinya.
- **Kotak "Poin Loyalitas" pelanggan baru tidak lagi berisi "0"** yang
  harus dihapus dulu sebelum bisa diisi.
- **Jumlah di Order Restock tidak lagi diambil dari angka stok.** Dulu
  jumlahnya adalah stok saat ini, sehingga produk berstok minus keluar
  sebagai "-104 Pres Lawet Ijo" — dan angkanya sama sekali tidak bisa
  diubah. Sekarang jumlahnya Anda tentukan sendiri.
- **Pemilih satuan & jumlah di Cek Stok kini juga muncul untuk produk yang
  sudah ditandai habis sebelumnya.** Dulu hanya muncul kalau produknya baru
  dicentang di sesi itu; produk yang sudah tercentang dari sebelumnya tampil
  tanpa satuan dan teksnya turun jadi "- Nama Produk" polos.
- **Nama satuan di Cek Stok terbaca jelas di mode gelap** (dulu warnanya
  dipaksa hitam sehingga nyaris tidak terlihat).
- **Angka stok tidak bisa lagi berbeda antar layar.** Untuk produk yang
  punya dua perubahan stok di detik yang sama, layar Cek Stok / Stock
  Opname / laporan inventori bisa menampilkan angka lama sementara
  perhitungan internal memakai angka terbaru. Sekarang semuanya konsisten.
- **Layar "Hitung Fisik" (Stock Opname) jauh lebih cepat terbuka** untuk
  toko dengan banyak produk — dulu menunggu memuat data satuan produk satu
  per satu sebelum daftarnya muncul.
- **Barcode yang sama tidak bisa lagi dipakai dua produk sekaligus.** Dulu
  menyimpan produk baru dengan barcode yang sudah dipakai produk lain
  "berhasil" tanpa peringatan apa pun — padahal diam-diam barcode itu
  DIAMBIL dari produk yang lama. Akibatnya produk lama tidak bisa di-scan
  lagi, dan men-scan kode tersebut di kasir menagih produk yang SALAH,
  tanpa ada tanda apa pun. Sekarang penyimpanan ditolak dengan pesan yang
  menyebutkan produk mana yang sudah memakai barcode itu. **Nama produk di
  pesan itu bisa langsung diketuk** untuk membuka produk tersebut — jadi
  kalau memang barcode-nya mau dipindahkan, tinggal ketuk namanya, hapus
  barcode di sana, lalu kembali dan simpan (isian yang sedang diketik tidak
  hilang). Barcode dari produk yang sudah dinonaktifkan tetap boleh dipakai
  ulang seperti biasa.

## 24 Juli 2026

### 🛠️ Perbaikan
- **Restore backup yang selalu gagal dengan pesan error** ("FOREIGN KEY
  constraint failed") sudah diperbaiki — sebelumnya toko yang pernah
  memakai fitur kategori-tambahan (satu produk masuk lebih dari satu
  kategori) tidak bisa restore backup APAPUN sama sekali. Sekalian
  kategori-tambahan dan reservasi nomor nota sekarang benar-benar ikut
  tersimpan di file backup (sebelumnya diam-diam terlewat).
- **Produk baru yang diusulkan asisten/pegawai kadang hilang begitu saja
  dari daftar tinjauan owner** setelah sync — sekarang tidak lagi. Bug ini
  muncul kalau ada dua HP kasir/asisten berbeda yang kebetulan tersambung
  dari alamat jaringan yang sama (biasa terjadi di hotspot HP).

## 23 Juli 2026

### ✨ Fitur Baru
- **Tombol Bayar baru di keranjang (cart bar)** — sekarang ada tombol "Bayar"
  warna terracotta di samping tombol "Tahan", langsung membuka layar
  Pembayaran (tidak perlu buka keranjang dulu). Tombol ini hanya muncul
  untuk owner, asisten, dan pegawai yang memang diberi izin menerima
  pembayaran.
- **Transfer transaksi lewat QR, kini bebas dipakai owner/asisten/pegawai
  berizin** — bukan cuma pegawai tanpa izin menerima pembayaran. Di
  keranjang, ada ikon baru (QR + panah) di sebelah tombol kosongkan untuk
  mengirim seluruh isi keranjang ke perangkat lain lewat QR — berguna kalau
  satu kasir belum bisa memproses transaksi dan perlu melempar ke kasir
  lain. Tombol "Kosongkan" sekarang berbentuk ikon tempat sampah (konfirmasi
  tetap ada sebelum benar-benar mengosongkan).
- **Nomor nota (mis. #17) sekarang tampil dari awal** — begitu barang
  pertama masuk keranjang, nomor notanya langsung ditetapkan dan tampil di
  cart bar serta di kartu pesanan yang ditahan. Nomor ini tidak berubah-ubah
  lagi sampai transaksi selesai, termasuk kalau transaksinya ditransfer ke
  perangkat lain lewat QR.
- **Transfer QR sekarang ikut membawa data pelanggan** — kalau transaksi
  yang ditransfer sudah punya pelanggan terpilih (bukan "Umum"), perangkat
  penerima otomatis mengenali pelanggan yang sama (kalau datanya sudah
  tersinkron), jadi tidak perlu pilih ulang manual.
- **Buka pesanan hasil transfer QR jadi lebih cepat** — sebelumnya harus
  centang satu-satu tiap barang dulu sebelum bisa lanjut ke keranjang;
  sekarang ketuk kartu pesanan langsung masuk ke keranjang, tanpa langkah
  centang lagi.

- **Satu produk sekarang bisa ada di lebih dari satu kategori.** Di layar
  Kelola Kategori, ketuk nama kategori untuk membuka daftar produk — centang
  produk yang mau dimasukkan ke kategori itu, langsung tersimpan seketika
  (tidak perlu tombol "Terapkan" lagi). Uncentang untuk mengeluarkan produk
  dari kategori itu saja — kategori lain yang sudah dipunyai produk tersebut
  TETAP ada, tidak ikut hilang. Daftar produk juga menampilkan harga & stok,
  serta keterangan "Juga ada di: ..." kalau produk sudah ada di kategori lain.
- **Kategori sekarang muncul juga di layar Kasir.** Tombol kecil di bawah
  bilah pencarian — ketuk untuk memfilter produk sesuai kategori itu, ketuk
  lagi untuk menampilkan semua produk kembali. Urutan tombol kategori bisa
  diatur sendiri: tekan agak lama lalu geser ke posisi yang diinginkan.

### 🛠️ Perbaikan
- Sheet "Tempel Pesanan" di Kasir — tombol konfirmasinya sempat tertutup
  keyboard saat mengetik, sekarang selalu terlihat penuh.

---

## 22 Juli 2026

### ✨ Fitur Baru
- **Sinkron Harga makin akurat, tidak ada lagi harga yang "berubah
  sendiri" walau sudah dicocokkan sebelumnya.** Setelah owner
  mencocokkan sebuah produk (misalnya lewat nama), aplikasi sekarang
  MENGINGAT pasangan itu secara permanen — sinkron berikutnya untuk
  produk yang sama langsung otomatis lewat barcode, tidak perlu
  ditinjau ulang lagi.
- Tab peninjauan produk mirip diganti jadi **"Perlu Ditinjau"**, dan
  ada tombol baru **"Terima Semua Kandidat Tunggal"** untuk konfirmasi
  cepat sekaligus.
- **Ekspor/Impor Katalog Harga (file terenkripsi)** di layar Sinkron
  Harga — untuk toko cabang yang tidak selalu satu WiFi dengan toko
  induk. Cara simpan/bagikannya sama seperti fitur Backup (bisa
  langsung share atau simpan ke perangkat).
- **Generate Barcode & Cetak Label** — produk yang belum punya barcode
  sama sekali (misalnya Telur/Kg yang dijual tanpa kemasan) sekarang
  bisa dibuatkan barcode otomatis langsung dari field Barcode di form
  Edit Produk (tombol di sebelah tombol Scan), lalu dicetak jadi label
  (nama, satuan, harga, barcode) dari layar Barcode produk lewat
  printer thermal yang sudah terpasang di toko — tidak perlu alat
  tambahan.

### 🛠️ Perbaikan
- Pencocokan produk "mirip nama" (fuzzy) yang kadang salah cocokkan
  produk berbeda varian (misalnya ukuran berbeda) sudah dihapus —
  sekarang hanya mencocokkan barcode, kode produk, atau nama+satuan
  yang benar-benar persis, sisanya diminta konfirmasi manual owner.
- **Produk yang dinonaktifkan owner sekarang benar-benar ikut hilang
  dari HP kasir/asisten setelah sync** — sebelumnya produk yang sudah
  dinonaktifkan (mis. sudah tidak dijual lagi) bisa tetap muncul
  selamanya di perangkat lain walau sudah tidak aktif di perangkat
  owner.
- **Cetak label sekarang selalu tampilkan kode batang**, apa pun format
  barcode produknya — sebelumnya barcode yang bukan format standar
  13-digit (banyak dipakai utk produk non-barcode resmi spt Telur/Kg)
  bisa gagal tampilkan kode batang sama sekali di label cetak.

## 21 Juli 2026

### ✨ Fitur Baru
- **Sync WiFi jadi makin ringan/cepat seiring waktu** — setelah data
  disetujui, sync berikutnya cuma mengirim data BARU saja, tidak lagi
  mengirim ulang semua data dari awal setiap kali.
- **Antrian sync yang menunggu persetujuan tidak lagi hilang** kalau HP
  owner ditutup/restart sebelum sempat ditinjau — sekarang tersimpan
  aman, bisa dilanjutkan kapan saja.
- Tombol **"Tolak"** di antrian sync sekarang minta **konfirmasi** dulu
  (data yang ditolak tidak akan otomatis muncul lagi).
- Tombol baru **"Sync Ulang Penuh"** di layar Sync — kalau owner memang
  ingin perangkat lain mengirim ulang semua datanya dari awal.
- **Notifikasi sync di tab manapun sekarang lebih rapi** — bentuknya jadi
  kartu (sama seperti notifikasi lain di app), muncul tepat di bawah
  header/toolbar tiap tab (bukan mengambang di atas segalanya), dan
  otomatis hilang begitu tidak ada lagi yang perlu ditinjau (sebelumnya
  "Host aktif" bisa menetap terus selama server sync menyala, walau
  semua sudah beres).
- **Usulan harga/produk dari kasir/asisten tidak lagi menumpuk** di layar
  review kalau isinya sudah sama persis dengan data owner — sebelumnya
  produk yang sudah tidak ada bedanya bisa terus muncul lagi setiap sync.
- **Notifikasi sync dirapikan lagi** — celah kosong aneh di atas kartu
  sudah hilang, dan di HP kasir/asisten, tampilan "menunggu persetujuan
  owner..." tidak lagi berputar tanpa henti selamanya — sekarang
  menampilkan konfirmasi singkat lalu hilang sendiri.

## 20 Juli 2026

### ✨ Fitur Baru
- **Tab baru "Laporan Pengeluaran"** di halaman Laporan — ringkasan total,
  grafik lingkaran (donut) per jenis pengeluaran, dan grafik batang harian.
- **Retur & koreksi barang di transaksi yang sudah lunas kini update nota
  yang sama** — tidak lagi bikin transaksi/struk baru terpisah. Barang yang
  diretur ditandai dengan pembatas "Retur HH:MM" di daftar barang, dan
  ringkasan struk menampilkan Total awal, jumlah Retur, Total akhir, serta
  Refund yang diberikan.
- **Sync WiFi: owner sekarang bisa pindah ke tab lain tanpa memutus proses
  sync** — sebelumnya, keluar dari layar Sync WiFi (mis. buka tab Kasir
  sebentar) langsung mematikan server, memutus koneksi kasir/asisten yang
  sedang mengirim data. Sekarang server tetap jalan di latar belakang, dan
  ada banner status kecil yang muncul di tab manapun selagi ada sync
  berjalan atau antrian menunggu persetujuan — tap untuk kembali ke layar
  Sync.

### 🎨 Penyempurnaan Tampilan
- **Tombol "000" di keypad pembayaran dipindah ke baris bawah**, sejajar
  dengan "0" dan "00" — lebih mudah dijangkau & konsisten posisinya.
- **Ringkasan struk (dalam aplikasi, share, cetak) disederhanakan jadi 3
  baris: Total, Dibayar, dan Sisa/Kembalian** — baris "Uang Diterima" yang
  sebelumnya bisa membingungkan (menampilkan jumlah tunai kotor per
  transaksi cicilan) dihapus. Poin yang didapat tetap ditampilkan.
- **Struk share & cetak tidak lagi menampilkan jejak internal** (baris edit
  harga/qty atau retur) — informasi itu untuk kebutuhan toko sendiri, bukan
  konsumsi pelanggan. Detail lengkapnya tetap tersimpan di struk dalam
  aplikasi.
- **Tambah Satuan baru di form produk kini langsung meloncat & fokus ke
  kolom harga** satuan yang baru ditambahkan — tidak perlu scroll manual
  lagi untuk mulai mengisi.

### 🐛 Perbaikan
- **Catatan struk (catatan item, catatan struk, footer) yang lebih dari
  satu baris kini tercetak utuh di printer thermal** — sebelumnya baris
  kedua dst. terpotong hilang saat dicetak (walau tampil normal di layar).
- **Baris "Dibayar" di struk kini menampilkan jumlah cicilan yang benar-
  benar dibayarkan** — sebelumnya, untuk transaksi lunas yang dibayar
  bertahap (beberapa kali tunai) dan ada kembalian, baris "Dibayar" salah
  menampilkan angka yang sama persis dengan "Total" (bukan jumlah uang
  yang sebenarnya diterima), sehingga tidak nyambung dengan baris
  Kembalian di bawahnya.
- **Sinkronisasi antar-HP (owner & asisten/kasir): transaksi yang diterima
  lewat sync kini selalu tampil lengkap dengan daftar barangnya** —
  sebelumnya, satu transaksi bermasalah bisa membuat daftar barang
  transaksi LAIN yang dikirim di waktu bersamaan ikut hilang di struk
  (hanya nomor nota, total, dan riwayat pembayaran yang tampil, daftar
  barang kosong).
- **Usulan perubahan harga dari HP asisten yang sudah disetujui owner
  tidak lagi terus muncul ulang** di layar sync — sebelumnya usulan yang
  sudah diterapkan bisa terus muncul kembali setiap kali sync, seolah
  belum pernah disetujui.
- **Perubahan harga/satuan dari HP asisten yang belum sempat disetujui
  owner tidak lagi hilang diam-diam** — sebelumnya, kalau asisten sync
  lagi untuk hal lain SEBELUM owner sempat meninjau usulan harganya,
  perubahan itu bisa tertimpa balik oleh harga lama milik owner tanpa
  pemberitahuan apa pun.
- **Struk cetak: baris "Produk: [jumlah]" sekarang sejajar dengan baris
  "Pegawai:"** di atasnya — sebelumnya nomornya menempel langsung setelah
  label, tidak lurus dengan baris pegawai.

## 19 Juli 2026

### 🎨 Penyempurnaan Tampilan
- **Struk (dalam aplikasi): jumlah & satuan barang kini dicetak tebal** —
  lebih mudah dibaca sekilas, tapi tetap lebih tipis dari nama produk.
- **Keranjang: jumlah barang di kiri item jadi teks biasa** (tanpa kotak),
  supaya nominal harga di sebelahnya tidak lagi terasa tertutup.
- **Tombol +/- kasir: angka tidak lagi "berkedip"** saat tombol + ditekan
  berkali-kali beruntun.
- **Tombol +/- kasir kini lebih responsif** — jeda anti-salah-pencet yang
  membuat penekanan cepat berturut-turut terasa lambat sudah dihapus.
- **Keypad kalkulator uang tunai diberi warna** — angka 1–9 hijau soft,
  tombol nol (0 / 00 / 000) biru bertahap, agar lebih mudah dibaca cepat.
- **Tombol "Bayar" di struk kini hijau tegas** sama seperti tombol Bayar
  di halaman pembayaran (sebelumnya hijau samar).
- **Menu Pengaturan lebih berwarna** — seksi Toko (hijau) dan Perangkat
  (teal) kini punya aksen warna soft seperti seksi lain.
- **Mode gelap:** angka pada tombol hijau (barang di keranjang) kini gelap
  agar terbaca jelas; tombol "Bayar Nanti" di pembayaran tidak lagi terlalu
  pucat (merah tegas).
- **Struk share & cetak kini menandai barang tambahan** — barang yang
  ditambahkan lewat "Tambah Belanjaan" dipisah baris "----- Tambahan
  HH:MM -----", sama seperti struk di dalam aplikasi (sebelumnya batas ini
  hanya ada di layar, hilang saat dibagikan/dicetak).

### ✨ Fitur Baru
- **Keranjang katalog pesanan (link WhatsApp) tidak lagi hilang saat
  di-refresh** — pilihan barang pelanggan kini tersimpan otomatis di
  browser, bertahan sampai 1 hari atau sampai toko generate ulang
  katalognya. Ditambah tombol "Kosongkan" untuk mulai pesanan batch baru.
- **Kartu baru "Selisih Kas Operasional" di Laporan Ringkasan** — Omzet
  dikurangi Pengeluaran (tanpa memperhitungkan modal barang), sebagai
  gambaran kas masuk vs kas keluar operasional, berdampingan dengan
  Laba Bersih yang sudah ada.

### 🛠️ Perbaikan
- **"Catatan di Struk" (Informasi Toko) kini benar-benar tampil di struk**
  — sebelumnya, teks yang Anda isi di sana (mis. "Terima kasih telah
  berbelanja") tidak pernah muncul; struk selalu menampilkan "Terima
  kasih!" bawaan. Sekarang berlaku di struk share, cetak, maupun nota
  gabungan (fallback ke "Terima kasih!" bila belum diisi).
- **Laporan Ringkasan kini cocok dengan transaksi sebenarnya setelah sync** —
  sebelumnya, transaksi dari kasir/asisten yang sudah masuk lewat sinkronisasi
  kadang tidak terhitung di Laporan Ringkasan (angka lebih kecil dari yang
  seharusnya, walau transaksinya sudah sama di kedua HP). Sekarang laporan
  otomatis membetulkan diri saat dibuka.
- **Usulan ubah harga dari kasir/asisten kini benar-benar diterapkan** —
  sebelumnya, saat owner menyetujui usulan perubahan harga, harga di HP
  owner tidak ikut berubah dan harga di HP asisten malah balik ke harga
  lama saat sinkronisasi. Sekarang harga baru diterapkan dengan benar di
  kedua perangkat.

### ✨ Fitur Baru
- **Cari produk berikutnya lebih cepat** — saat Anda menyentuh kolom cari
  di kasir lagi sementara kata pencarian sebelumnya masih ada, seluruh kata
  otomatis tersorot. Tinggal ketik langsung untuk menggantinya (tak perlu
  lagi menghapus satu per satu atau menjangkau tombol × di atas), atau geser
  kursor bila hanya ingin mengoreksi sebagian.

---

## 18 Juli 2026

### ✨ Fitur Baru
- **Peringatan stok menipis muncul di kasir setelah jualan** — begitu
  sebuah produk terjual dan stoknya turun sampai/di bawah batas minimum
  yang Anda set, saat kembali ke layar kasir muncul notifikasi singkat
  (± 5 detik, bisa ditutup): mis. "Stok Gula menipis: sisa 100 biji
  (5 pak, 1 dus)" — stok dalam satuan dasar plus konversi ke satuan lain
  dalam kurung.
- **Pengeluaran bisa difilter per periode** — di layar Pengeluaran,
  pilih Hari Ini / Minggu Ini / Bulan Ini / rentang tanggal Custom;
  total & daftar ikut menyesuaikan (sebelumnya selalu bulan berjalan).
- **Angka jumlah barang kini juga tampil di kiri tiap item di keranjang**
  (di samping kotak centang), tidak cuma di tombol +/- sebelah kanan.
- **Tombol +/- kasir: angka jumlah berpindah ke sisi berlawanan dari
  tombol yang baru ditekan** — begitu tombol ditekan, tombol itu jadi
  ikon polos dan angkanya pindah ke tombol satunya (supaya angka tidak
  ketutup jempol). Kembali normal saat menyentuh area lain / scroll.
- **Tombol +/- di kasir kini punya "pijakan jempol"** — setelah ditap,
  tombol membesar dan TETAP besar (bukan cuma sesaat) supaya tap
  berikutnya (mis. nambah qty lagi) lebih besar targetnya dan tidak
  gampang salah pencet. Mengecil lagi otomatis begitu tap di tempat
  lain atau mulai scroll.
- **Kelola Kategori kini bisa "Tambah Massal"** (tambah banyak kategori
  sekaligus, satu nama per baris) dan **hapus banyak sekaligus** (tekan
  lama salah satu kategori untuk masuk mode pilih).
- **Backup & Restore dan Alihkan Owner kini bisa langsung "Bagikan"** —
  selain disimpan ke penyimpanan HP, file backup terenkripsi bisa langsung
  dikirim ke Google Drive/WhatsApp/email dll lewat menu bagikan bawaan HP,
  tanpa perlu tersimpan di HP dulu.
- **Kartu-kartu di layar Ringkasan, Laporan, dan Pengaturan kini punya
  warna lembut sesuai fungsinya** — hijau untuk uang/kas, amber untuk
  stok, merah untuk hutang/hal mendesak, biru untuk produk, ungu untuk
  sinkronisasi — supaya lebih cepat dikenali sekilas.

### 🔧 Perbaikan
- **Kartu "Usulan Harga/Produk" di layar Sync WiFi tidak lagi tampil
  berantakan** — sebelumnya di HP dengan layar sempit, teks IP & jumlah
  produk di kartu itu bisa terpotong jadi satu huruf per baris (susah
  dibaca). Sekarang tampil rapi satu baris seperti seharusnya.

### 🛡️ Keamanan & Keandalan Data
- **Stok kini dihitung ulang dengan benar setelah sinkronisasi antar-HP** —
  sebelumnya, kalau HP kasir dan HP owner sama-sama mencatat pergerakan
  stok lalu sync, angka stok bisa diam-diam "melompat" mengikuti pandangan
  salah satu HP saja (penjualan dari HP lain seolah hilang dari hitungan).
  Sekarang seluruh pergerakan dari kedua HP digabung dan dihitung ulang
  urut waktu, jadi angka stok selalu jumlah yang sebenarnya.
- **Layar penyelamat "Kunci Toko Tidak Terbaca"** — di HP tertentu, sistem
  penyimpanan aman Android bisa sesekali gagal dibaca. Dulu kondisi ini
  membuat aplikasi tampak "ter-reset" ke layar setup dan data seolah
  hilang. Sekarang muncul layar khusus dengan tombol "Coba Lagi"
  (biasanya beres setelah HP di-restart) — data Anda tidak disentuh
  sama sekali.
- **Password backup minimal 8 karakter** — file backup/alihan owner hanya
  sekuat password-nya; ekspor baru kini mewajibkan minimal 8 karakter.
  File backup lama dengan password pendek tetap bisa dibuka seperti biasa.
- **Pesan "Password salah" yang konsisten saat memulihkan backup** — dulu
  dalam kasus langka, password salah bisa memunculkan error teknis yang
  membingungkan alih-alih pesan yang jelas.
- **Aplikasi lebih hemat memori saat sinkronisasi data besar** — sync toko
  dengan riwayat panjang tidak lagi berisiko membuat aplikasi tertutup
  sendiri di HP dengan RAM kecil.

### ✨ Fitur Baru
- **Usulan harga/produk dari kasir/asisten kini bisa direview owner sebelum
  masuk ke data toko** — kalau kasir/asisten sempat ubah harga produk atau
  tambah produk baru langsung di HP-nya, perubahan itu TIDAK langsung
  menimpa data owner saat sync. Owner akan melihat daftar "Usulan
  Harga/Produk" di layar Sinkronisasi, bisa lihat harga lama vs baru
  (atau detail produk baru), pilih mana yang mau diterapkan, baru tekan
  "Terapkan". Usulan yang belum ditinjau tetap aman dan akan muncul lagi
  di sync berikutnya.
- **Layar Sync WiFi kini punya pengaturan "Batas Waktu Tunggu (Timeout)"**
  — bisa dipilih Cepat/Normal/Lambat/Sangat Lambat. Kalau toko Anda punya
  riwayat data besar atau WiFi yang cenderung lemot sehingga sync sering
  gagal timeout padahal sebenarnya masih berjalan, naikkan ke profil yang
  lebih longgar.
- **Tombol "Refresh IP" baru di kartu "Jadi Host"** — kalau IP HP owner
  berubah setelah server dinyalakan (ganti jaringan, HP baru reconnect
  WiFi), tekan tombol ini supaya QR/IP yang dibagikan ke kasir selalu yang
  terbaru, tanpa perlu matikan-nyalakan ulang server.

### 🔧 Perbaikan
- **Pesan error sync WiFi sekarang lebih jelas & actionable** kalau gagal
  terhubung — misalnya menyebutkan kemungkinan router memblokir koneksi
  antar-HP (fitur "isolasi klien" WiFi), HP owner mengunci layar/pindah
  app sehingga koneksi terputus otomatis, atau HP kasir sedang pakai jalur
  data seluler alih-alih WiFi. Deteksi IP host juga dibuat lebih andal
  (pakai cara cadangan otomatis kalau cara utama gagal di HP tertentu).
- **Struk cetak & struk gambar (share) sekarang menampilkan kembalian yang
  benar** — sebelumnya, kalau kembalian yang sudah pernah diberikan
  dipakai lagi sebagai pembayaran (mis. saat "Tambah Belanjaan"), baris
  "Kembali" di struk bisa menampilkan angka yang salah (akumulasi dari
  seluruh riwayat pembayaran nota, bukan kembalian yang baru saja
  diberikan). Sekarang selalu menampilkan kembalian dari pembayaran
  TERAKHIR, konsisten dengan Ringkasan di layar.

## 17 Juli 2026

### ✨ Fitur Baru
- **Katalog HTML kini otomatis menandai "Stok Habis"** dari stok riil
  (bukan cuma tanda manual) — kalau toggle "Izinkan Stok Minus" di
  Pengaturan sedang OFF dan stok sistem sebuah produk sudah 0, katalog
  yang dibagikan ke pelanggan otomatis menampilkan badge "Stok Habis"
  walau kasir lupa menandainya manual.
- **Layar baru "Cek Stok"** (ikon 📦 di AppBar tab Produk, atau kartu
  "Kontrol Stok" di Ringkasan Harian) — lihat semua produk diurut dari
  yang stoknya paling tipis, difilter per kategori. Centang produk yang
  memang habis: otomatis menandai "Stok Habis" di sistem SEKALIGUS
  menyusun teks pesanan restock yang bisa langsung disalin atau dikirim
  ke supplier.
- **Kartu "Kontrol Stok" baru di Ringkasan Harian** — ringkasan cepat
  berapa produk stok menipis/habis, dengan pratinjau produk paling
  kritis dan tombol "Lihat semua" ke layar Cek Stok.
- **Tab baru "Stok" di Laporan** — nilai total inventori (stok × harga
  pokok) sekarang, dipecah per kategori (grafik donat + tabel), termasuk
  peringatan kalau ada produk yang harga pokoknya belum diisi (supaya
  Anda tahu angkanya belum lengkap) dan daftar produk yang stoknya
  sedang negatif. Laporan ini melengkapi stock opname fisik, bukan
  menggantikannya.
- **Tutup Buku sekarang bisa pakai tanggal custom** (tidak harus selalu
  1 Januari) — cocok untuk toko yang tutup buku mengikuti Hari Raya,
  yang tanggalnya berubah tiap tahun. Tetap sekali per tahun, tinggal
  pilih tanggal akhir periode lewat kalender.
- **Opsi "Sinkron via barcode saja"** di layar Sinkron Harga — untuk
  toko dengan kode produk yang tidak konsisten, bisa memilih mode yang
  hanya mencocokkan lewat barcode (lebih lambat prosesnya tapi paling
  akurat).
- **Fitur baru "Stock Opname"** (ikon ✅ di layar Cek Stok) — hitung
  fisik stok toko secara BUTA (angka stok sistem sengaja disembunyikan
  saat Anda mengetik hasil hitungan, supaya tidak bias ke angka lama),
  baru dibandingkan dengan stok sistem di layar review sebelum disimpan.
  Bisa untuk sebagian kategori saja atau seluruh produk sekaligus. Ada
  riwayat semua sesi opname yang pernah dilakukan, lengkap dengan
  rincian selisih per produk.
- **Katalog kini bisa dipublish otomatis ke web** — tombol "Publish ke
  Web" baru di layar Katalog Pesanan (berdampingan dengan "Buat &
  Bagikan" manual yang sudah ada). Setelah isi Account ID + API Token
  Cloudflare sekali (gratis, lihat tombol ☁️ di AppBar), setiap tekan
  "Publish ke Web" katalog otomatis ter-upload dan dapat link tetap yang
  bisa dibagikan sekali ke pelanggan — update harga berikutnya, link-nya
  tidak berubah, tinggal publish ulang.

### 🔧 Perbaikan
- **Sinkron harga antar-toko tidak lagi salah mengubah harga produk yang
  tak berhubungan.** Sebelumnya, saat menyamakan harga dengan toko lain,
  sering muncul "harga berubah" untuk produk yang seharusnya tidak
  tersentuh — bahkan setiap kali sinkron ulang selalu ada saja yang
  berubah. Penyebabnya: produk yang **kode-nya sama** (mis. banyak produk
  memakai kode "Dos"/"Pak"/"Bal") tertukar satu sama lain. Sekarang, kalau
  sebuah kode dipakai lebih dari satu produk, aplikasi **tidak menebak** —
  item seperti itu dilempar ke tab "Mirip" untuk Anda konfirmasi manual,
  dan pencocokan lewat kode juga mengharuskan satuannya benar-benar cocok.
  Sinkron harga jadi jauh lebih akurat dan tidak "berubah-ubah sendiri".
- **Menambah/mengedit varian produk dengan barcode yang sudah dipakai
  produk lain sekarang menampilkan pesan error yang jelas** — sebelumnya
  varian gagal tersimpan tanpa pemberitahuan apa pun (terlihat seperti
  tidak terjadi apa-apa), sekarang muncul pesan "Barcode sudah dipakai
  produk/varian lain" supaya Anda tahu perlu pakai barcode lain.
- **Barcode produk/varian yang dinonaktifkan/dihapus sekarang benar-benar
  bebas dipakai ulang.** Sebelumnya, barcode produk yang sudah "dihapus"
  tetap terkunci selamanya (data produk memang cuma disembunyikan, bukan
  dihapus total, tapi barcode-nya dulu ikut tersangkut) — jadi kalau Anda
  ingin gabungkan beberapa produk lama jadi satu produk dengan varian (mis.
  "Pop Ice" dengan varian Coklat/Stroberi, dari yang sebelumnya 2 produk
  terpisah), barcode lama tidak bisa dipasang lagi ke produk/varian baru.
  Sekarang begitu produk/varian dinonaktifkan, barcode-nya otomatis
  dilepas dan siap dipakai produk lain.
- **Asisten yang sudah diberi izin "Izinkan Stok Minus" oleh owner
  sekarang benar-benar bisa memakainya saat toko pakai 2 HP terpisah.**
  Sebelumnya, kalau HP asisten kebetulan yang dijadikan "Jadi Host" saat
  sinkron (bukan HP owner), perubahan izin yang dibuat owner tidak pernah
  sampai ke HP asisten — izin terlihat menyala di HP owner tapi asisten
  tetap ditolak dengan pesan "Stok tidak cukup". Sekarang tombol "Jadi
  Host" di layar Sync WiFi hanya muncul di HP owner — owner selalu jadi
  sumber data utama, kasir & asisten selalu jadi yang menyambung ke
  owner, supaya semua perubahan (izin, harga, produk) pasti tersalur.
- **Sinkron WiFi tidak lagi bisa "loading selamanya" tanpa kabar apa
  pun** — sekaligus tidak lagi salah putus transfer yang sebenarnya
  masih berjalan normal. Sebelumnya, kalau ada gangguan jaringan sesaat
  (mis. WiFi tertentu memblokir HP-ke-HP walau satu jaringan yang sama),
  tombol "Sync" di HP kasir/asisten bisa berputar tanpa henti — tidak
  pernah berhasil maupun gagal, dan HP owner juga tidak pernah tahu ada
  percobaan sync yang bermasalah. Sekarang sinkron otomatis berhenti &
  menampilkan pesan error yang jelas kalau BENAR-BENAR tidak ada respons
  sama sekali — tapi toko dengan data banyak (sync pertama kali,
  katalog/riwayat besar) yang wajar makan waktu lebih lama tetap
  dibiarkan selesai selama datanya terus mengalir, tidak lagi ikut
  terputus paksa.

## 16 Juli 2026

### 🎨 Perubahan Tampilan
- **Header struk didesain ulang** — kotak besar "Transaksi Berhasil"/
  "Transaksi Tempo" di atas struk sudah tidak ada lagi. Status Lunas/Tempo
  sekarang tampil sebagai watermark stempel samar di belakang daftar
  barang (hijau untuk Lunas, merah untuk Tempo), lengkap dengan nomor nota
  di dalamnya — nama & harga barang tetap selalu terbaca jelas, berapa pun
  banyaknya barang di nota. Tombol "Tandai Semua" juga diringkas jadi
  ikon bulat kecil (hijau), senada dengan lingkaran jumlah barang yang
  sudah ada.
- Nama produk di baris item struk in-app sekarang lebih tebal (bold),
  lebih mudah dibaca sekilas.
- **Tombol toolbar di layar Kasir** (scan barcode, antrian, riwayat
  transaksi, tempel pesanan) sekarang punya aksen warna soft sesuai
  fungsinya masing-masing — lebih mudah dibedakan sekilas, tidak lagi
  seragam abu-abu semua.

### ✨ Fitur Baru
- **Nota tempo yang belum dibayar sama sekali kini bisa menaikkan jumlah
  barang langsung dari modal edit item struk** — sebelumnya cuma bisa
  dikurangi/dihapus, sekarang jumlahnya bisa ditambah lagi kalau ternyata
  kurang (khusus nota yang belum ada pembayaran masuk sama sekali).
- **Fitur baru "Alihkan Owner"** (Pengaturan → Sinkronisasi) — pindahkan
  seluruh data DAN identitas toko ke HP lain lewat file terenkripsi
  (beda dari Backup & Restore biasa yang cuma memindahkan data). Berguna
  kalau ganti HP owner, atau HP lama kehabisan baterai/rusak — HP baru
  bisa langsung "menjadi" toko yang sama tanpa perlu setup ulang atau
  pairing manual ke kasir/asisten yang sudah ada.
- **Opsi baru "Pulihkan dari File" di layar awal** (sebelum setup toko) —
  kalau sudah punya file backup atau file Alihan Owner, sekarang bisa
  langsung dipulihkan dari layar pertama tanpa perlu bikin toko dummy
  dulu.

### 🐛 Perbaikan Bug
- **Poin loyalitas sekarang bertambah sesuai kenaikan nominal saat
  "Tambah Belanjaan"** — sebelumnya kalau nota yang sudah dapat poin
  ditambah barang lagi, poin tambahannya tidak pernah dihitung. Sekarang
  poin ikut bertambah proporsional dengan total nota yang baru.
- Alamat pelanggan yang sempat belum tampil di beberapa dropdown pencarian
  pelanggan (mis. dari tab kasir) sekarang ikut muncul, konsisten dengan
  tempat lain.
- **Poin loyalitas tidak lagi nyangkut di pelanggan lama** kalau nama
  pelanggan pada nota diubah balik ke "Umum" atau diganti ke pelanggan
  lain — poin yang sudah diberikan sekarang otomatis ditarik balik dari
  pelanggan lama, lalu dihitung ulang untuk pelanggan baru (kalau ada).
- **App tidak lagi bisa "macet" di halaman "Page Not Found" setelah hapus
  data aplikasi atau install ulang** — sebelumnya bisa terjadi kondisi
  aplikasi bolak-balik antara layar aktivasi & layar setup tanpa henti,
  sekarang selalu tuntas berhenti di layar aktivasi.
- **Scan barcode dobel cepat berturut sekarang lebih responsif** — jeda
  anti-duplikat untuk scanner eksternal diturunkan (300ms → 150ms),
  supaya scan dobel yang memang disengaja (mis. mau nambah qty 2) tidak
  ikut ke-abaikan.
- **Riwayat transaksi tidak lagi menampilkan "Pelanggan" generik** untuk
  nota lama milik pelanggan yang sudah dihapus — nama aslinya sekarang
  tetap tampil, sesuai seharusnya (riwayat historis memang dirancang
  tidak ikut hilang saat pelanggan dihapus).

## 15 Juli 2026

### ✨ Fitur Baru
- **Sisa waktu lisensi ditampilkan di Pengaturan** — di kartu "Device Ini",
  sekarang terlihat berapa lama lagi masa aktif aplikasi, otomatis
  menyesuaikan satuan (hari, lalu jam, lalu menit saat mendekati habis).
- **Kirim katalog via WhatsApp bisa diatur langsung ke nomor toko atau
  share biasa** — di Pengaturan > Katalog Pesanan, sekarang ada saklar
  untuk memilih apakah tombol "Kirim via WhatsApp" di katalog pelanggan
  langsung membuka chat ke nomor WA toko, atau membiarkan pelanggan
  memilih sendiri kontak tujuannya.

### 🎨 Perubahan Tampilan
- Field Pelanggan & Pegawai di modal checkout sekarang sejajar
  berdampingan, tidak lagi ditumpuk — lebih ringkas.
- Beberapa keterangan yang terlalu panjang di modal checkout diringkas
  (mis. "Pegawai (yang melayani)" menjadi "Pegawai").
- Warna tombol "Bayar" di in-app struk sekarang sama dengan tombol Bayar
  di modal checkout.
- Alamat pelanggan kini ditampilkan di bawah nama pada semua daftar
  saran pelanggan — membantu membedakan pelanggan dengan nama yang sama.

### 🐛 Perbaikan Bug
- **Poin loyalitas tidak masuk saat pelanggan diubah dari "Umum" ke
  pelanggan terdaftar di in-app struk** — sekarang poin otomatis dihitung
  begitu nama pelanggan diisi/diubah di struk, tidak cuma saat checkout.
- Tombol "Transaksi Baru" di in-app struk dihapus karena sudah bisa lewat
  tab Kasir di bawah.
- Angka desimal (mis. 0,25 untuk produk timbang) sekarang tampil dengan
  benar di lingkaran stepper +/- dan di notifikasi hasil scan barcode —
  sebelumnya terpotong/tidak proporsional.
- Tap ganda yang sangat cepat pada stepper +/- (kemungkinan salah pencet)
  sekarang diabaikan supaya jumlah tidak bertambah tanpa sengaja.
- **Struk gabungan (nota digabung) dengan banyak barang tidak lagi buram
  saat dibagikan** — sebelumnya kalau nota yang digabung berisi banyak
  sekali barang (puluhan item dari beberapa nota), gambar struk yang
  dikirim lewat WhatsApp jadi sangat panjang dan otomatis dikompresi
  habis-habisan sampai tulisannya tidak terbaca sama sekali. Sekarang
  dikirim sebagai file PDF (bukan foto), jadi tetap jelas dibaca berapa
  pun banyaknya barang.

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
- **App sekarang meminta kode aktivasi** saat pertama kali dibuka setelah
  update ini — berlaku untuk semua device, termasuk yang sudah lama
  dipakai. Kode aktivasi didapat dari penyedia app, sekali dimasukkan
  tidak perlu diulang lagi (kecuali masa berlakunya habis).

### 🎨 Tampilan
- **Badge jumlah item di struk & keranjang kini bentuknya sama persis
  dengan badge di bar keranjang** (lingkaran terracotta berisi angka) —
  di struk, badge ini menempel di sudut kartu daftar barang; di
  keranjang, tampil di samping nominal Total.
- **Kartu antrian "Pesanan Ditahan" dirombak** — sebelumnya pesanan
  handoff dari pegawai punya tab lipat merah di atas kartu yang bikin
  tampilan tidak rapi & sebagian kartu jadi punya ruang kosong besar di
  bawahnya. Sekarang semua kartu (pesanan ditahan biasa maupun kiriman
  pegawai) tampil rapi dalam bentuk yang sama — beda status cukup lewat
  label kecil berwarna di atas kartu (abu-abu netral "Ditahan" atau
  terracotta bertuliskan nama pegawai pengirim).
- **Panel "Pesanan Ditahan" sekarang bisa ditutup dengan tap/geser di
  layar** — tidak perlu selalu tekan tombol (✕) lagi, tap di mana saja
  di luar wadah panel langsung menutupnya dengan animasi halus.

### 🐛 Perbaikan Bug
- **Sync ke owner/asisten tidak lagi gagal total dengan pesan error
  teknis** (mis. "table transactions has no column named ...") kalau HP
  kasir belum sempat update ke versi app terbaru — data yang bisa
  disinkronkan tetap masuk, cuma bagian yang belum dikenal HP itu saja
  yang dilewati.
- **Transaksi "Bayar Nanti" (tempo/hutang) sekarang ikut mendapat poin
  loyalitas** kalau totalnya melebihi ambang batas yang ditentukan di
  Pengaturan — sebelumnya poin selalu 0 utk transaksi tempo apapun
  besar nominalnya, walau pelanggan sudah pasti akan menepati janji
  bayarnya. Kalau transaksinya kemudian dibatalkan, poin ikut otomatis
  ditarik kembali seperti transaksi tunai biasa.
- **Katalog online tidak lagi terasa berat/nge-lag** saat pelanggan
  menambah/mengurangi jumlah barang — sebelumnya tiap tap tombol +/-
  membangun ulang seluruh daftar produk, terasa makin berat untuk toko
  dengan banyak produk. Sekarang cuma barang yang disentuh saja yang
  diperbarui, tampilannya sama persis seperti sebelumnya.

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
