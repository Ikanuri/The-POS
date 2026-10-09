# Analisis QR Scanner Telegram (CameraScanActivity) — bingkai yang "mengikuti" QR

Sumber: `TMessagesProj/src/main/java/org/telegram/ui/CameraScanActivity.java` (1428 baris) di DrKLO/Telegram. Dipakai untuk "Hubungkan Perangkat" (Link Desktop Device, `TYPE_QR_LOGIN`), scan QR umum (`TYPE_QR`), bot web (`TYPE_QR_WEB_BOT`), dan paspor MRZ (`TYPE_MRZ`).

## 1. Tumpukan teknologi
| Lapisan | Teknologi | Peran |
|---|---|---|
| Kamera | `messenger/camera/CameraView` + **Camera2** (`Camera2Session`) / legacy `Camera`; preview di **TextureView** | Pratinjau layar penuh; `setOptimizeForBarcode(true)`, `setUseMaxPreview(true)` (resolusi tinggi, fokus untuk barcode) |
| Deteksi utama | **Google Play Services Vision** `BarcodeDetector` (`play-services-vision:20.1.3`) | Mengembalikan **teks + `cornerPoints` (4 titik sudut QR dalam piksel gambar)** |
| Deteksi cadangan | **ZXing** `QRCodeReader` + `GlobalHistogramBinarizer` (`zxing:core:3.5.4`) | Dipakai bila Vision tidak tersedia (`isOperational()` false, mis. HP tanpa GMS) |
| Pra-proses | `invert(bitmap)` lalu `monochrome(bitmap, 90)` | Percobaan ulang bila gagal: QR putih-di-hitam & kontras rendah |
| Thread | `HandlerThread("ScanCamera")` | Decode di thread latar, UI hanya menggambar |
| Animasi | `androidx.dynamicanimation` **SpringAnimation/SpringForce** + `ValueAnimator` + `CubicBezierInterpolator` | Bingkai muncul membal, pindah halus |
| Gambar | `Canvas` di `ViewGroup.drawChild` (bukan View terpisah) | Menggambar redup + sudut bingkai di atas anak kamera |

## 2. Alur logika (tanpa pengenalan "frame-by-frame" dari kamera)
1. Setelah kamera siap (`cameraView.setDelegate`) -> `startRecognizing()` menjalankan `requestShot`.
2. **Polling, bukan callback preview**: `requestShot` memfokus ke tengah (`focusToPoint`), lalu `processShot(cameraView.getTextureView().getBitmap())` — mengambil **snapshot bitmap dari TextureView** di thread latar.
3. `tryReadQr(...)` -> Vision `detect(Frame)`; bila nihil: coba bitmap terbalik, lalu monokrom; bila Vision tak ada -> ZXing.
4. Hasil dinormalisasi: `cornerPoints` dibagi lebar/tinggi gambar -> **koordinat 0..1** (`toPointF`), `bounds` = kotak minimum yang melingkupi 4 titik + padding (25dp horizontal, 15dp vertikal) lalu dibagi lebar/tinggi.
5. QR dengan awalan salah (mis. bukan `tg://login?token=`) ditolak (`TYPE_QR_LOGIN`).
6. **Setelah QR pertama ditemukan, polling dipercepat**: `sps` (sampel per detik) = 8 / 24 / 40 sesuai kelas performa HP (rendah/menengah/tinggi); jeda = `max(16, 1000/sps - rata2WaktuProses)` ms. Jadi bingkai di-update ~24–40x/dtk saat QR terkunci.
7. Selesai bila: QR tanpa batas (`bounds==null`, kasus pertama) ATAU sudah >1 detik terkunci dan tak ada pemuatan (`qrLoading`). Hilang dari pandangan >4 kali berturut-turut = `recognized=false`, bingkai kembali ke posisi tengah.
8. Delegate `processQr` memungkinkan layar pemanggil memvalidasi (mis. memuat token ke server) SEBELUM menutup; selama itu bingkai tetap menempel.

## 3. Mengapa bingkai "bergerak mengikuti QR"
Tiga mekanisme digabung:
1. **Sumber posisi nyata**: tiap sampel memberi 4 sudut QR (piksel) -> dinormalisasi ke 0..1. Posisi bingkai adalah posisi QR sesungguhnya di preview, bukan animasi buatan.
2. **Interpolasi linear 75 ms (`boundsUpdateDuration`)**: tiap hasil baru menyimpan `fromBounds/fromPoints` (posisi yang sedang ditampilkan) dan `bounds/points` (target). `getRecognizedBounds()` menghitung `t = (now - lastBoundsUpdate)/75ms` lalu `lerp(from, to, t)` SETIAP frame gambar, dan memanggil `invalidate()` selama `t<1`. Karena sampel datang tiap ~25–40 ms namun interpolasi 75 ms, gerak terlihat **halus & sedikit tertinggal (low-pass)**, bukan melompat tiap sampel.
3. **Cross-fade antara "kotak diam" dan "kotak terkunci"**: `getBounds()` = `lerp(normalBounds, recognizedBounds, useRecognizedBounds)`. `useRecognizedBounds` digerakkan **SpringAnimation** (damping 1.0, stiffness 500) dari 0 -> 1 saat QR terdeteksi (dan 1 -> 0 saat hilang). `normalBounds` = kotak tengah sisi `min(w,h)/1.5`. Hasilnya bingkai "menyedot" dari kotak tengah ke QR dengan fisika pegas, bukan teleport.

Elemen visual (`drawChild`): (a) 4 persegi panjang gelap di luar bingkai (alpha 0.5 -> 0.75 saat terkunci), (b) isian gelap di dalam bingkai memudar saat `qrAppearingValue` naik, (c) **4 sudut berbentuk "pil sudut"** digambar sebagai `Path` dengan `arcTo` (lebar 4dp, panjang kaki 20dp; saat awal kaki = sisi kotak penuh lalu mengecil ke 20dp lewat `lerp(..., pow(qrAppearingValue,1.8))`), (d) ukuran bingkai `x(0.5 + 0.5*qrAppearing)` — muncul membesar dari setengah ukuran dgn pegas (damping 0.8, stiffness 250). Titik 4 sudut asli (`getPoints()`, yang bisa miring/perspektif) sudah dihitung & diinterpolasi tetapi gambarnya dikomentari (debug) — yang dipakai hanya kotak sumbu-sejajar `bounds`.

## 4. Mengapa tidak memakai stream preview?
Memakai `TextureView.getBitmap()` + polling memberi kendali laju (hemat baterai di HP lemah: 8 sps) dan menyatukan jalur kamera/galeri (gambar dari galeri memakai `tryReadQr` yang sama). Biayanya: bitmap penuh tiap sampel (lebih berat dari YUV), diimbangi `sps` adaptif.

## 5. Padanan untuk The POS (Flutter, `mobile_scanner ^5.2.3`)
- `mobile_scanner` sudah memberi **`Barcode.corners` (List<Offset>, 4 titik)** dan ukuran gambar (`BarcodeCapture.size`) lewat stream `onDetect` — setara `cornerPoints`; tidak perlu polling bitmap. Di Android memakai **ML Kit** (setara Vision), di iOS Vision.
- Resep penerapan: (1) simpan target `corners` ternormalisasi (dibagi `capture.size`) — NB: perlu memetakan orientasi/rotasi preview & `BoxFit.cover` ke koordinat layar; (2) `AnimationController` 75 ms per sampel untuk lerp dari posisi tampil -> target; (3) `SpringSimulation` (damping 1.0 / stiffness 500) untuk `useRecognized` 0..1 yang meng-lerp kotak tengah <-> kotak QR; (4) `CustomPainter` di atas `MobileScanner`: 4 persegi redup di luar bingkai + 4 sudut `Path` melengkung; (5) reset ke tengah bila tak terdeteksi >4 sampel; (6) tunda tutup layar ~1 dtk setelah terkunci (atau sampai validasi selesai).
- Titik rawan: pemetaan koordinat (rotasi 90°, mirror kamera depan, `BoxFit.cover` memotong sisi), frekuensi `onDetect` (bawaan `DetectionSpeed.normal` + `detectionTimeoutMs: 250` = hanya ~4 hasil/dtk; untuk gerak mulus pakai `DetectionSpeed.unrestricted` atau timeout ~30–40 ms, dan tetap lerp 75 ms), dan uji hanya mungkin di perangkat nyata.
