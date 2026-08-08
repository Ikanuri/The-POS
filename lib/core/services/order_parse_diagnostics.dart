/// Item 55 — logging diagnostik SEMENTARA untuk investigasi bug "Tempel
/// Pesanan pegawai (non `terima_pembayaran`) tidak dapat produk dari QR/
/// teks owner, padahal ASISTEN yang menerima teks PERSIS SAMA berhasil".
/// Tiga hipotesis (ID salah di sisi owner, bug encode multi-item, percabangan
/// kode berdasar role) sudah disingkirkan via pembacaan kode statis — butuh
/// bukti runtime dari device pegawai yang GAGAL, bukan teori lagi.
///
/// In-memory saja (TIDAK ditulis ke Downloads/file publik sama sekali —
/// permintaan eksplisit user), cukup untuk satu sesi reproduksi. Dibaca via
/// `ParseDiagnosticsScreen` (tombol sementara di `PasteOrderSheet`).
///
/// WAJIB DICABUT TOTAL (file ini, titik `.add()` di `OrderParserService.
/// parse()`, `ParseDiagnosticsScreen`, tombol aksesnya) begitu root cause bug
/// di atas ketemu & fix-nya sudah dieksekusi — bukan cuma dimatikan via flag.
class OrderParseDiagnostics {
  OrderParseDiagnostics._();

  static const _maxEntries = 200;

  static final List<String> entries = [];

  static void add(String entry) {
    entries.add(entry);
    while (entries.length > _maxEntries) {
      entries.removeAt(0);
    }
  }

  static void clear() => entries.clear();
}
