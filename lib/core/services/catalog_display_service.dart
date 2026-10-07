import '../database/app_database.dart';

/// Pengaturan TAMPILAN katalog HTML (halaman awal, kategori, saran terlaris,
/// pengumuman, "Pesan lagi"). Disimpan di tabel settings & didaftarkan di
/// [AppDatabase.syncableSettingKeys] supaya seragam di semua perangkat toko.
///
/// Semua default AMAN: toko yang belum menyentuh pengaturan ini mendapat
/// katalog dengan kategori ON, terlaris 30 hari, pengumuman mati, "Pesan
/// lagi" ON.
class CatalogDisplay {
  const CatalogDisplay({
    this.showCategories = true,
    this.topDays = 30,
    this.topFrom,
    this.topTo,
    this.topCount = 8,
    this.announceEnabled = false,
    this.announceText = '',
    this.reorderEnabled = true,
  });

  /// Maks karakter teks pengumuman (kotak popup kecil di HP pelanggan).
  static const maxAnnounceChars = 280;
  static const topCountMin = 3;
  static const topCountMax = 12;
  static const topCountDefault = 8;

  /// Pilihan periode preset (hari ke belakang dari saat Publish).
  static const periodPresets = [7, 30, 90];

  final bool showCategories;

  /// 7/30/90 = preset; 0 = rentang tanggal sendiri ([topFrom]..[topTo]).
  final int topDays;
  final DateTime? topFrom;
  final DateTime? topTo;
  final int topCount;
  final bool announceEnabled;
  final String announceText;
  final bool reorderEnabled;

  bool get isCustomRange => topDays == 0 && topFrom != null && topTo != null;

  /// Teks pengumuman yang benar-benar dipakai (trim + dipotong 280 karakter).
  String get effectiveAnnouncement => clampAnnouncement(announceText);

  /// Pengumuman tampil di katalog hanya bila toggle ON DAN teks tidak kosong.
  bool get hasAnnouncement =>
      announceEnabled && effectiveAnnouncement.isNotEmpty;

  static String clampAnnouncement(String s) {
    final t = s.trim();
    final runes = t.runes;
    if (runes.length <= maxAnnounceChars) return t;
    return String.fromCharCodes(runes.take(maxAnnounceChars)).trim();
  }

  /// Lama pengumuman tampil otomatis di katalog (ms) — rumus yang SAMA
  /// dengan JS katalog: clamp(3000 + 60 ms x jumlah huruf, 3000, 12000).
  static int announceAutoMs(String text) =>
      (3000 + 60 * text.length).clamp(3000, 12000);

  /// Rentang [from, to] yang dihitung untuk terlaris. Preset: mundur
  /// [topDays] hari dari [now]. Rentang sendiri: awal hari `topFrom` s/d
  /// akhir hari `topTo` (urutan terbalik dibetulkan).
  ({DateTime from, DateTime to}) topRange(DateTime now) {
    if (isCustomRange) {
      var a = topFrom!;
      var b = topTo!;
      if (b.isBefore(a)) {
        final t = a;
        a = b;
        b = t;
      }
      return (
        from: DateTime(a.year, a.month, a.day),
        to: DateTime(b.year, b.month, b.day, 23, 59, 59),
      );
    }
    final days = periodPresets.contains(topDays) ? topDays : 30;
    return (from: now.subtract(Duration(days: days)), to: now);
  }

  CatalogDisplay copyWith({
    bool? showCategories,
    int? topDays,
    DateTime? topFrom,
    DateTime? topTo,
    int? topCount,
    bool? announceEnabled,
    String? announceText,
    bool? reorderEnabled,
  }) =>
      CatalogDisplay(
        showCategories: showCategories ?? this.showCategories,
        topDays: topDays ?? this.topDays,
        topFrom: topFrom ?? this.topFrom,
        topTo: topTo ?? this.topTo,
        topCount: topCount ?? this.topCount,
        announceEnabled: announceEnabled ?? this.announceEnabled,
        announceText: announceText ?? this.announceText,
        reorderEnabled: reorderEnabled ?? this.reorderEnabled,
      );
}

class CatalogDisplayService {
  CatalogDisplayService._();

  static const showCategoriesKey = 'katalog_show_categories';
  static const topDaysKey = 'katalog_top_days'; // '7' | '30' | '90' | 'range'
  static const topFromKey = 'katalog_top_from'; // yyyy-MM-dd
  static const topToKey = 'katalog_top_to'; // yyyy-MM-dd
  static const topCountKey = 'katalog_top_count';
  static const announceEnabledKey = 'katalog_announce_enabled';
  static const announceTextKey = 'katalog_announce_text';
  static const reorderKey = 'katalog_reorder_enabled';

  /// Semua key — didaftarkan ke `AppDatabase.syncableSettingKeys`.
  static const allKeys = [
    showCategoriesKey,
    topDaysKey,
    topFromKey,
    topToKey,
    topCountKey,
    announceEnabledKey,
    announceTextKey,
    reorderKey,
  ];

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseYmd(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  static Future<CatalogDisplay> load(AppDatabase db) async {
    final cats = await db.getSetting(showCategoriesKey);
    final daysRaw = await db.getSetting(topDaysKey);
    final from = _parseYmd(await db.getSetting(topFromKey));
    final to = _parseYmd(await db.getSetting(topToKey));
    final count = int.tryParse(await db.getSetting(topCountKey) ?? '');
    final annEn = await db.getSetting(announceEnabledKey);
    final annText = await db.getSetting(announceTextKey) ?? '';
    final reorder = await db.getSetting(reorderKey);

    var days = 30;
    if (daysRaw == 'range') {
      // Rentang tak lengkap/rusak -> jatuh ke default 30 hari.
      days = (from != null && to != null) ? 0 : 30;
    } else {
      final d = int.tryParse(daysRaw ?? '');
      if (d != null && CatalogDisplay.periodPresets.contains(d)) days = d;
    }
    return CatalogDisplay(
      showCategories: cats == null || cats == '1',
      topDays: days,
      topFrom: from,
      topTo: to,
      topCount: (count ?? CatalogDisplay.topCountDefault)
          .clamp(CatalogDisplay.topCountMin, CatalogDisplay.topCountMax),
      announceEnabled: annEn == '1',
      announceText: annText,
      reorderEnabled: reorder == null || reorder == '1',
    );
  }

  static Future<void> setShowCategories(AppDatabase db, bool v) =>
      db.setSetting(showCategoriesKey, v ? '1' : '0');

  static Future<void> setTopPreset(AppDatabase db, int days) =>
      db.setSetting(topDaysKey, '$days');

  static Future<void> setTopRange(
      AppDatabase db, DateTime from, DateTime to) async {
    await db.setSetting(topFromKey, _ymd(from));
    await db.setSetting(topToKey, _ymd(to));
    await db.setSetting(topDaysKey, 'range');
  }

  static Future<void> setTopCount(AppDatabase db, int n) => db.setSetting(
      topCountKey,
      '${n.clamp(CatalogDisplay.topCountMin, CatalogDisplay.topCountMax)}');

  static Future<void> setAnnounceEnabled(AppDatabase db, bool v) =>
      db.setSetting(announceEnabledKey, v ? '1' : '0');

  static Future<void> setAnnounceText(AppDatabase db, String text) =>
      db.setSetting(announceTextKey, text);

  static Future<void> setReorderEnabled(AppDatabase db, bool v) =>
      db.setSetting(reorderKey, v ? '1' : '0');
}
