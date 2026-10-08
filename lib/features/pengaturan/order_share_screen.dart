import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/catalog_access_service.dart';
import '../../core/services/catalog_display_service.dart';
import '../../core/services/catalog_sticker_service.dart';
import '../../core/services/cloudflare_publish_service.dart';
import '../../core/services/order_page_service.dart';
import '../../core/theme/app_theme.dart';

/// Generate & bagikan katalog pesanan HTML — file statis self-contained
/// (tanpa server/hosting) yang bisa dibuka pelanggan dari WhatsApp untuk
/// memilih barang sendiri, lalu kirim balik teks pesanan.
///
/// Item 37 — SELAIN alur share manual (bawaan awal), owner bisa isi
/// Account ID + API Token Cloudflare sekali di sini lalu tekan "Publish ke
/// Web": katalog otomatis ter-upload ke Cloudflare Pages & dapat URL tetap
/// (`<project>.pages.dev`) yang bisa dibagikan sekali ke pelanggan — publish
/// berikutnya (mis. setelah harga berubah) cukup tekan tombol yang sama
/// lagi, URL TIDAK berubah. Fitur ini OPSIONAL & fallback-nya tetap alur
/// share manual di bawah (offline-first: ekspor katalog tidak boleh
/// bergantung ke internet).
class OrderShareScreen extends ConsumerStatefulWidget {
  const OrderShareScreen({super.key, this.cloudflare});

  /// Layanan publish; null = bawaan. Hanya di-inject oleh test.
  final CloudflarePublishService? cloudflare;

  @override
  ConsumerState<OrderShareScreen> createState() => _OrderShareScreenState();
}

/// Jam buka katalog (toko tutup) — lihat `CatalogAccessService`.
final _hoursProvider = FutureProvider<CatalogHours>((ref) async {
  final db = ref.watch(databaseProvider);
  return CatalogAccessService.loadHours(db);
});

/// Item 12 — toggle direct WA (wa.me ke nomor toko) vs share generik.
/// Default ON (true) supaya perilaku lama tetap sama sebelum user mengatur.
final _waDirectProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('katalog_wa_direct');
  return v == null || v == '1';
});

/// Pengaturan tampilan katalog (kategori, terlaris, pengumuman, Pesan lagi).
final _displayProvider = FutureProvider<CatalogDisplay>((ref) async {
  final db = ref.watch(databaseProvider);
  return CatalogDisplayService.load(db);
});

/// Slot stiker mana yang memakai unggahan sendiri (bukan bawaan).
final _stickerCustomProvider =
    FutureProvider<Map<StickerSlot, bool>>((ref) async {
  final db = ref.watch(databaseProvider);
  return {
    for (final s in StickerSlot.values)
      s: await CatalogStickerService.isCustom(db, s),
  };
});

const _idMonthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Tanggal pendek tanpa `DateFormat` ber-locale (app tidak pernah
/// `initializeDateFormatting` -> `DateFormat(..., 'id_ID')` meledak).
String _shortDate(DateTime d, {bool withYear = false}) =>
    '${d.day} ${_idMonthsShort[d.month - 1]}${withYear ? ' ${d.year}' : ''}';

class _OrderShareScreenState extends ConsumerState<OrderShareScreen> {
  final _announceCtrl = TextEditingController();
  bool _announceLoaded = false;

  @override
  void dispose() {
    _announceCtrl.dispose();
    super.dispose();
  }

  bool _generating = false;
  int? _lastProductCount;
  DateTime? _lastGeneratedAt;

  late final CloudflarePublishService _cloudflare =
      widget.cloudflare ?? CloudflarePublishService();
  bool _publishing = false;
  String? _publishedUrl;

  Future<String> _buildHtml() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final storeName = (await db.getSetting('store_name'))?.trim();
    final storeWhatsapp = (await db.getSetting('store_whatsapp'))?.trim() ?? '';
    final storeTelegram = (await db.getSetting('store_telegram'))?.trim() ?? '';
    final name =
        (storeName == null || storeName.isEmpty) ? device.storeName : storeName;
    final waDirect = ref.read(_waDirectProvider).valueOrNull ?? true;
    final result = await OrderPageService.generateHtml(
      db: db,
      storeName: name,
      storeWhatsapp: storeWhatsapp,
      storeTelegram: storeTelegram,
      waDirect: waDirect,
    );
    if (mounted) {
      setState(() {
        _lastProductCount = result.productCount;
        _lastGeneratedAt = DateTime.now();
      });
    }
    return result.html;
  }

  Future<void> _saveHours(CatalogHours h) async {
    await CatalogAccessService.saveHours(ref.read(databaseProvider), h);
    ref.invalidate(_hoursProvider);
  }

  Future<void> _pickTime(CatalogHours h, {required bool open}) async {
    final cur = open ? h.openMinutes : h.closeMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    await _saveHours(
        open ? h.copyWith(openMinutes: m) : h.copyWith(closeMinutes: m));
  }

  /// Jam buka katalog + tombol darurat "Tutup sekarang". Jadwal berjalan
  /// sendiri di halaman katalog (tak perlu Publish tiap pagi/malam); Publish
  /// ulang hanya perlu saat jadwal/tombol darurat berubah.
  Widget _buildHoursCard() {
    final h = ref.watch(_hoursProvider).valueOrNull ?? const CatalogHours();
    return Column(
      children: [
        SwitchListTile(
          key: const ValueKey('hours-enabled'),
          secondary: const Icon(Icons.schedule),
          title: const Text('Atur jam buka katalog'),
          subtitle: Text(h.enabled
              ? 'Di luar jam buka, katalog tampil tutup (abu-abu, harga '
                  'disembunyikan)'
              : 'Mati: katalog selalu buka'),
          value: h.enabled,
          onChanged: (v) => _saveHours(h.copyWith(enabled: v)),
        ),
        if (h.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('hours-open'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    onPressed: () => _pickTime(h, open: true),
                    child: Text('Buka ${CatalogHours.hhmm(h.openMinutes)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('hours-close'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    onPressed: () => _pickTime(h, open: false),
                    child: Text('Tutup ${CatalogHours.hhmm(h.closeMinutes)}'),
                  ),
                ),
              ],
            ),
          ),
        SwitchListTile(
          key: const ValueKey('hours-forced'),
          secondary: Icon(Icons.store_mall_directory_outlined,
              color:
                  h.forcedClosed ? Theme.of(context).colorScheme.error : null),
          title: const Text('Tutup sekarang'),
          subtitle:
              const Text('Libur/darurat: katalog tutup walau dalam jam buka'),
          value: h.forcedClosed,
          onChanged: (v) => _saveHours(h.copyWith(forcedClosed: v)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Berlaku di katalog setelah Publish/bagikan ulang.',
                style: TextStyle(fontSize: 11.5)),
          ),
        ),
      ],
    );
  }

  // ── Tampilan katalog (kategori, terlaris, pengumuman, Pesan lagi) ──────

  Future<void> _saveDisplay(Future<void> Function(AppDatabase db) save) async {
    await save(ref.read(databaseProvider));
    ref.invalidate(_displayProvider);
  }

  Widget _sectionLabel(String text, {bool badge = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  color: scheme.onSurfaceVariant)),
          if (badge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2F7D4F),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('BARU',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Future<void> _pickTopRange(CatalogDisplay d) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: d.isCustomRange
          ? DateTimeRange(start: d.topFrom!, end: d.topTo!)
          : DateTimeRange(
              start: today.subtract(const Duration(days: 30)), end: today),
      helpText: 'Periode penjualan terlaris',
    );
    if (picked == null) return;
    await _saveDisplay((db) =>
        CatalogDisplayService.setTopRange(db, picked.start, picked.end));
  }

  Widget _buildTopSellersCard(CatalogDisplay d) {
    final scheme = Theme.of(context).colorScheme;
    String rangeLabel() {
      final a = d.topFrom!, b = d.topTo!;
      return '${_shortDate(a, withYear: a.year != b.year)} - '
          '${_shortDate(b, withYear: true)}';
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Periode penjualan yang dihitung saat Publish:',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in CatalogDisplay.periodPresets)
                ChoiceChip(
                  key: ValueKey('top-days-$days'),
                  label: Text('$days hari'),
                  selected: d.topDays == days,
                  onSelected: (_) => _saveDisplay(
                      (db) => CatalogDisplayService.setTopPreset(db, days)),
                ),
              ChoiceChip(
                key: const ValueKey('top-range'),
                avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                label:
                    Text(d.isCustomRange ? rangeLabel() : 'Pilih tanggal...'),
                selected: d.isCustomRange,
                onSelected: (_) => _pickTopRange(d),
              ),
            ],
          ),
          const Divider(height: 26),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Jumlah saran',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Nama produk yang berganti di kolom cari',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TopCountDropdown(
                value: d.topCount,
                onChanged: (n) => _saveDisplay(
                    (db) => CatalogDisplayService.setTopCount(db, n)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Nama saran diambil persis dari nama produk di katalog. Tanpa '
              'data penjualan di periode itu, kolom cari memakai teks umum.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(CatalogDisplay d) {
    final scheme = Theme.of(context).colorScheme;
    // Isi field diambil SEKALI dari DB (jangan ditimpa tiap provider
    // refresh — kursor/ketikan user hilang).
    if (!_announceLoaded && ref.watch(_displayProvider).hasValue) {
      _announceLoaded = true;
      _announceCtrl.text = d.announceText;
    }
    final text = CatalogDisplay.clampAnnouncement(_announceCtrl.text);
    final secs = (CatalogDisplay.announceAutoMs(text) / 1000).round();
    return Column(
      children: [
        SwitchListTile(
          key: const ValueKey('announce-enabled'),
          secondary: const Icon(Icons.campaign_outlined),
          title: const Text('Tampilkan pengumuman'),
          subtitle: const Text('Muncul otomatis sekali tiap link dibuka, lalu '
              'bisa dibuka lewat tombol megafon. Teks kosong = tombol tidak '
              'tampil.'),
          value: d.announceEnabled,
          onChanged: (v) => _saveDisplay(
              (db) => CatalogDisplayService.setAnnounceEnabled(db, v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: TextField(
            key: const ValueKey('announce-text'),
            controller: _announceCtrl,
            maxLength: CatalogDisplay.maxAnnounceChars,
            maxLines: 4,
            minLines: 2,
            buildCounter: (_,
                    {required currentLength,
                    required isFocused,
                    required maxLength}) =>
                null,
            decoration: const InputDecoration(
              hintText: 'mis. Besok toko tutup lebih awal pukul 15.00',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              setState(() {});
              ref
                  .read(databaseProvider)
                  .setSetting(CatalogDisplayService.announceTextKey, v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${text.runes.length} / ${CatalogDisplay.maxAnnounceChars}'
              '${text.isEmpty ? '' : ' · tampil otomatis ± $secs detik'}',
              key: const ValueKey('announce-counter'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickSticker(StickerSlot slot) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final v = CatalogStickerService.validateTgs(result.files.single.bytes!);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (v.json == null) {
      messenger.showSnackBar(SnackBar(
          content: Text(v.error ?? 'Stiker tidak valid'),
          backgroundColor: Theme.of(context).colorScheme.error));
      return;
    }
    await CatalogStickerService.setCustom(
        ref.read(databaseProvider), slot, result.files.single.bytes!);
    ref.invalidate(_stickerCustomProvider);
    messenger.showSnackBar(SnackBar(
        content: Text('Stiker "${slot.label}" diganti - berlaku setelah '
            'Publish/bagikan ulang')));
  }

  Future<void> _resetSticker(StickerSlot slot) async {
    await CatalogStickerService.resetToDefault(
        ref.read(databaseProvider), slot);
    ref.invalidate(_stickerCustomProvider);
  }

  /// Empat stiker animasi katalog (.tgs): bawaan aplikasi, bisa diganti.
  Widget _buildStickersCard() {
    final custom = ref.watch(_stickerCustomProvider).valueOrNull ?? const {};
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final slot in StickerSlot.values)
          ListTile(
            key: ValueKey('sticker-${slot.name}'),
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: Text(slot.label),
            subtitle: Text(custom[slot] == true ? 'Unggahan sendiri' : 'Bawaan'),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (custom[slot] == true)
                  TextButton(
                    key: ValueKey('sticker-reset-${slot.name}'),
                    onPressed: () => _resetSticker(slot),
                    child: const Text('Bawaan'),
                  ),
                TextButton(
                  key: ValueKey('sticker-pick-${slot.name}'),
                  onPressed: () => _pickSticker(slot),
                  child: const Text('Ganti'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                'Ganti dengan berkas stiker animasi .tgs (format stiker '
                'Telegram, maks 64 KB). Berkas tidak valid ditolak.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }

  /// Bagian "tampilan katalog": kategori, saran terlaris, pengumuman toko &
  /// Pesan lagi — mengikuti mockup (satu kartu per bagian).
  List<Widget> _buildDisplaySections() {
    final d = ref.watch(_displayProvider).valueOrNull ?? const CatalogDisplay();
    return [
      _sectionLabel('Tampilan katalog'),
      Card(
        child: SwitchListTile(
          key: const ValueKey('display-categories'),
          secondary: const Icon(Icons.grid_view_rounded),
          title: const Text('Tampilkan kategori'),
          subtitle: const Text(
              'Pelanggan memilih kategori dulu di halaman awal (chip "Semua '
              'produk" tetap ada) dan label kategori tampil di tiap produk. '
              'Dimatikan: halaman awal hanya punya satu chip "Semua produk".'),
          value: d.showCategories,
          onChanged: (v) => _saveDisplay(
              (db) => CatalogDisplayService.setShowCategories(db, v)),
        ),
      ),
      _sectionLabel('Saran produk terlaris di kolom cari'),
      Card(child: _buildTopSellersCard(d)),
      _sectionLabel('Pengumuman toko'),
      Card(child: _buildAnnouncementCard(d)),
      _sectionLabel('Pesan lagi (di HP pelanggan)'),
      Card(
        child: SwitchListTile(
          key: const ValueKey('display-reorder'),
          secondary: const Icon(Icons.replay_rounded),
          title: const Text('Tampilkan "Pesan lagi"'),
          subtitle: const Text(
              'Riwayat pesanan tersimpan di HP pelanggan sendiri (bukan di '
              'server). Bila datanya terhapus, pelanggan bisa menempel pesan '
              'lama dari WhatsApp.'),
          value: d.reorderEnabled,
          onChanged: (v) => _saveDisplay(
              (db) => CatalogDisplayService.setReorderEnabled(db, v)),
        ),
      ),
      _sectionLabel('Game di katalog'),
      Card(
        child: SwitchListTile(
          key: const ValueKey('display-game'),
          secondary: const Icon(Icons.sports_esports_outlined),
          title: const Text('Tampilkan game labirin'),
          subtitle: const Text(
              'Game bola di labirin (3 tingkat, bisa dengan memiringkan HP) '
              'di bawah halaman awal dan halaman toko tutup — hiburan '
              'sambil menunggu. Dimatikan: tidak tampil sama sekali.'),
          value: d.gameEnabled,
          onChanged: (v) => _saveDisplay(
              (db) => CatalogDisplayService.setGameEnabled(db, v)),
        ),
      ),
      _sectionLabel('Stiker animasi'),
      Card(child: _buildStickersCard()),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
            'Semua pengaturan di atas berlaku di katalog setelah '
            'Publish/bagikan ulang.',
            style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
      _sectionLabel('Yang sudah ada', badge: false),
    ];
  }

  Future<void> _openCloudflareSettings() async {
    final creds = await _cloudflare.loadCredentials();
    if (!mounted) return;
    final tokenCtrl = TextEditingController(text: creds?.apiToken ?? '');
    final accountCtrl = TextEditingController(text: creds?.accountId ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pengaturan Cloudflare Pages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Buat akun Cloudflare gratis (kalau belum punya), lalu ambil '
              'Account ID (sidebar kanan dashboard) & buat API Token '
              '(My Profile > API Tokens, scope: Account > Cloudflare '
              'Pages > Edit).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: accountCtrl,
              decoration: const InputDecoration(labelText: 'Account ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tokenCtrl,
              decoration: const InputDecoration(labelText: 'API Token'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final token = tokenCtrl.text.trim();
      final accountId = accountCtrl.text.trim();
      if (token.isEmpty || accountId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Account ID & API Token tidak boleh kosong')));
        }
        return;
      }
      await _cloudflare.saveCredentials(apiToken: token, accountId: accountId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kredensial Cloudflare disimpan')));
      }
    }
  }

  Future<void> _publishToWeb() async {
    if (_publishing) return;
    final messenger = ScaffoldMessenger.of(context);
    // Cek kredensial DULU (tanpa spinner) — spinner hanya utk kerja network
    // sungguhan. Kalau spinner dinyalakan sebelum dialog Pengaturan dibuka,
    // ikon animasinya berputar TAK TERBATAS selama dialog menunggu input
    // user, yang bikin `pumpAndSettle` widget test macet (ketahuan lewat
    // test — lihat order_share_publish_button_test.dart).
    var creds = await _cloudflare.loadCredentials();
    if (creds == null) {
      if (!mounted) return;
      await _openCloudflareSettings();
      if (!mounted) return;
      creds = await _cloudflare.loadCredentials();
      if (creds == null) return;
    }

    setState(() => _publishing = true);
    try {
      final html = await _buildHtml();
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final storeName = (await db.getSetting('store_name'))?.trim();
      final name = (storeName == null || storeName.isEmpty)
          ? device.storeName
          : storeName;
      final result = await _cloudflare.publish(
        html: html,
        storeName: name,
        storeUuid: device.storeUuid ?? name,
      );
      if (mounted) {
        setState(() => _publishedUrl = result.url);
        messenger.showSnackBar(
            SnackBar(content: Text('Berhasil publish ke ${result.url}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Gagal publish ke web: $e — coba lagi atau pakai '
              '"Buat & Bagikan" manual di bawah')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _generateAndShare() async {
    if (_generating) return;
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final storeName = (await db.getSetting('store_name'))?.trim();
      final name = (storeName == null || storeName.isEmpty)
          ? device.storeName
          : storeName;
      final html = await _buildHtml();

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/katalog_pesanan_$stamp.html');
      await file.writeAsString(html);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html')],
        text: 'Katalog pesanan $name — buka & pilih barang, lalu kirim '
            'balik pesanannya ke kami via WhatsApp.',
      );
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Gagal membuat katalog: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Katalog Pesanan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Pengaturan Cloudflare Pages',
            onPressed: _openCloudflareSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cara kerja',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const _StepLine(
                      no: 1,
                      text: 'Tekan "Buat & Bagikan" — satu file HTML berisi '
                          'seluruh katalog aktif (harga & varian) dibuat.'),
                  const _StepLine(
                      no: 2,
                      text: 'Kirim file itu ke pelanggan lewat WhatsApp '
                          '(atau simpan, kirim belakangan).'),
                  const _StepLine(
                      no: 3,
                      text: 'Pelanggan buka file itu di HP-nya (tanpa perlu '
                          'internet), pilih barang, lalu tekan "Kirim via '
                          'WhatsApp" — teks pesanan otomatis terformat rapi.'),
                  const _StepLine(
                      no: 4,
                      text: 'Kasir baca teks itu dan input manual seperti '
                          'biasa. (Tempel-otomatis ke keranjang menyusul di '
                          'tahap berikutnya.)'),
                ],
              ),
            ),
          ),
          ..._buildDisplaySections(),
          Card(
            child: Builder(builder: (context) {
              final waDirect = ref.watch(_waDirectProvider).valueOrNull ?? true;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.chat_outlined),
                    title: const Text('Kirim Langsung ke Nomor WA Toko'),
                    subtitle: Text(waDirect
                        ? 'Tombol "Kirim via WhatsApp" di katalog langsung buka '
                            'chat ke nomor WA toko'
                        : 'Tombol "Kirim via WhatsApp" biarkan pelanggan pilih '
                            'sendiri kontak tujuan (share biasa)'),
                    value: waDirect,
                    onChanged: (v) async {
                      final db = ref.read(databaseProvider);
                      await db.setSetting('katalog_wa_direct', v ? '1' : '0');
                      ref.invalidate(_waDirectProvider);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tombol "Kirim ke Telegram" muncul di halaman Pesanan '
                        'bila kolom Telegram di Informasi Toko diisi.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 8),
          Card(child: _buildHoursCard()),
          const SizedBox(height: 8),
          Card(
            color: scheme.errorContainer.withOpacity(0.4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File TIDAK otomatis ter-update. Setiap harga berubah, '
                      'buat & kirim ulang file ke pelanggan langganan.',
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _publishing ? null : _publishToWeb,
            icon: _publishing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_publishing ? 'Mempublish…' : 'Publish ke Web'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
          if (_publishedUrl != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: SelectableText(
                    _publishedUrl!,
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ),
                IconButton(
                  key: const ValueKey('copy-published-url'),
                  tooltip: 'Salin link',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _publishedUrl!));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                          const SnackBar(content: Text('Link disalin')));
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _generating ? null : _generateAndShare,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.ios_share),
            label: Text(_generating ? 'Membuat…' : 'Buat & Bagikan Katalog'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (_lastGeneratedAt != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${_lastProductCount ?? 0} produk · dibagikan '
                '${_lastGeneratedAt!.hour.toString().padLeft(2, '0')}:'
                '${_lastGeneratedAt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.no, required this.text});
  final int no;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$no',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}

/// Dropdown jumlah saran: bukan `DropdownButton` bawaan Flutter. Tombol pil
/// (angka + chevron) membuka kartu pilihan buatan sendiri yang menempel di
/// bawah tombol: tiap baris 48 px, pilihan aktif berwarna aksen + centang,
/// angka memakai font angka app. Tutup dengan memilih atau mengetuk di luar.
class _TopCountDropdown extends StatefulWidget {
  const _TopCountDropdown({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_TopCountDropdown> createState() => _TopCountDropdownState();
}

class _TopCountDropdownState extends State<_TopCountDropdown> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  static const _itemH = 48.0;
  static const _menuW = 132.0;

  bool get _open => _entry != null;

  void _toggle() => _open ? _close() : _show();

  void _show() {
    final values = [
      for (var n = CatalogDisplay.topCountMin;
          n <= CatalogDisplay.topCountMax;
          n++)
        n
    ];
    _entry = OverlayEntry(builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('top-count-barrier'),
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                  scale: 0.94 + 0.06 * t,
                  alignment: Alignment.topRight,
                  child: child),
            ),
            child: Material(
              key: const ValueKey('top-count-menu'),
              color: scheme.surface,
              elevation: 6,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: _menuW, maxHeight: _itemH * 5.5),
                child: SizedBox(
                  width: _menuW,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    children: [
                      for (final n in values)
                        _TopCountOption(
                          n: n,
                          selected: n == widget.value,
                          onTap: () {
                            _close();
                            if (n != widget.value) widget.onChanged(n);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        label: 'Jumlah saran, ${widget.value}',
        child: Material(
          color: scheme.primary.withOpacity(_open ? 0.14 : 0.08),
          shape: StadiumBorder(
              side: BorderSide(
                  color: scheme.primary.withOpacity(_open ? 0.7 : 0.35))),
          child: InkWell(
            key: const ValueKey('top-count-dropdown'),
            customBorder: const StadiumBorder(),
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 84, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${widget.value}',
                      key: const ValueKey('top-count-value'),
                      style: AppTheme.numStyle(context,
                          size: 20, weight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopCountOption extends StatelessWidget {
  const _TopCountOption(
      {required this.n, required this.selected, required this.onTap});

  final int n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('top-count-opt-$n'),
      onTap: onTap,
      child: Container(
        height: _TopCountDropdownState._itemH,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: selected ? scheme.primary.withOpacity(0.10) : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$n',
                style: AppTheme.numStyle(context,
                    size: 19,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.primary : null),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
