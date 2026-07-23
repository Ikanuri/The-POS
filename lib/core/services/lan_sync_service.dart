import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../database/app_database.dart';
import 'crash_log_service.dart';
import 'crypto_service.dart';
import 'tutup_buku_service.dart';

/// Profil timeout sync (Item 39) — beberapa toko punya data jauh lebih besar
/// (sync pertama kali, riwayat panjang) atau jaringan WiFi yang lemot/tidak
/// stabil, jadi default 10s/30s bisa kepotong sebelum transfer selesai.
/// Disimpan sbg key `app_settings` (`sync_timeout_profile`), dipilih owner/
/// kasir di layar Sync WiFi, dibaca ulang tiap mau sync (bukan tersimpan di
/// memori — supaya konsisten walau app di-restart di antara sync).
enum SyncTimeoutProfile {
  cepat('cepat', 'Cepat (LAN bagus)', Duration(seconds: 5), Duration(seconds: 15)),
  normal('normal', 'Normal (default)', Duration(seconds: 10), Duration(seconds: 30)),
  lambat('lambat', 'Lambat (data besar/WiFi lemot)', Duration(seconds: 20), Duration(seconds: 90)),
  sangatLambat('sangat_lambat', 'Sangat Lambat (toko besar)', Duration(seconds: 30), Duration(seconds: 180));

  const SyncTimeoutProfile(this.key, this.label, this.connectTimeout, this.responseTimeout);
  final String key;
  final String label;
  final Duration connectTimeout;
  final Duration responseTimeout;

  static const _kSettingKey = 'sync_timeout_profile';

  static SyncTimeoutProfile fromKey(String? key) =>
      values.firstWhere((p) => p.key == key, orElse: () => normal);

  static Future<SyncTimeoutProfile> load(AppDatabase db) async {
    final raw = await db.getSetting(_kSettingKey);
    return fromKey(raw);
  }

  static Future<void> save(AppDatabase db, SyncTimeoutProfile profile) =>
      db.setSetting(_kSettingKey, profile.key);
}

const _kSyncPort = 8625;
// 50 MB max payload — protects the host from memory-exhaustion DoS.
const _kMaxPayloadBytes = 50 * 1024 * 1024;

// B-3: nonce cache untuk mencegah replay. Cache per-session (bersih saat
// stopHost dipanggil). TTL efektif = masa hidup server (satu sesi sync).
final _usedNonces = <String>{};

String _generateNonce() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Hasil sync satu arah (diterima dari remote).
class SyncResult {
  const SyncResult({
    required this.received,
    required this.sent,
    this.pendingApproval = false,
  });
  final int received;
  final int sent;

  /// true jika data yang dikirim klien sedang menunggu persetujuan owner.
  final bool pendingApproval;
}

/// Item antrian sync menunggu persetujuan owner.
class PendingSyncItem {
  PendingSyncItem({
    required this.id,
    required this.fromIp,
    required this.arrivedAt,
    required this.tables,
    required this.since,
    required this.tablesSummary,
  });

  final String id;
  final String fromIp;
  final DateTime arrivedAt;
  final Map<String, List<Map<String, Object?>>> tables;
  final DateTime since;

  /// Human-readable: "3 transaksi, 8 item"
  final String tablesSummary;
}

/// Item 40 — usulan harga/produk dari device non-owner, ANTRIAN TERPISAH
/// dari [PendingSyncItem] (data append-only transaksi/stok/dll). Sengaja
/// dipisah supaya alur setuju/tolak salah satu TIDAK saling mengganggu
/// (mis. owner sudah setuju data transaksi tapi belum sempat tinjau
/// usulan harga — keduanya independen, bukan satu paket all-or-nothing).
class PendingProductProposal {
  PendingProductProposal({
    required this.id,
    required this.fromIp,
    required this.arrivedAt,
    required this.rows,
    required this.productCount,
  });

  final String id;
  final String fromIp;
  final DateTime arrivedAt;
  final Map<String, List<Map<String, Object?>>> rows;
  final int productCount;
}

class LanSyncService {
  LanSyncService._();

  static HttpServer? _server;
  static String? _syncToken;
  static String? _storeKey;
  static AppDatabase? _db;

  /// Seam test-only: isi `_db` tanpa `startHost()` sungguhan (bind
  /// `HttpServer` asli terbukti bikin `testWidgets` hang — lihat dok
  /// `debugHostRunningOverride`). Dipakai bersama seam itu utk test widget
  /// yang perlu antrian `sync_upload_queue` terisi (mis. tombol Tolak/
  /// Setuju), tanpa pernah menyentuh socket sungguhan.
  @visibleForTesting
  static void debugSetDb(AppDatabase db) => _db = db;

  /// Pasang referensi DB SEGERA saat app hidup (dipanggil `SyncStateNotifier`
  /// saat dibuat) — TANPA ini, `_db` tetap `null` sampai owner tap "Mulai
  /// Sebagai Host" secara eksplisit, sehingga antrian `sync_upload_queue`
  /// (yang sebenarnya SUDAH persisten & selamat dari app di-force-stop/clear
  /// RAM) tampak "hilang" di layar Sync sampai host direstart manual — bug
  /// nyata dilaporkan user, produk akhir Item 17 Fase 2 seharusnya membuat
  /// antrian itu terasa TIDAK hilang sama sekali. Aman dipanggil berkali-kali
  /// (idempotent); `startHost()` menimpa dgn instance yang sama.
  static void attachDb(AppDatabase db) => _db = db;

  // Simple per-IP brute-force protection: 5 failures → 5-min lockout.
  static final _failedAttempts = <String, int>{};
  static final _lockoutUntil = <String, DateTime>{};
  static const _kMaxFailures = 5;
  static const _kLockoutDuration = Duration(minutes: 5);

  // Callback dipanggil saat antrian berubah (UI bisa listen & re-query).
  static void Function()? onQueueChanged;

  /// Item 17 Fase 2 — antrian approval sync sisi host, sekarang PERSISTEN
  /// (baca dari `sync_upload_queue`, bukan `List` di memori lagi — lihat
  /// dok `AppDatabase.enqueueSyncUpload`). ASYNC krn butuh query DB;
  /// pemanggil (mis. provider UI) harus re-query lewat ini tiap
  /// [onQueueChanged] terpicu, bukan cache List seperti pola lama.
  static Future<List<PendingSyncItem>> loadPendingQueue() async {
    // Device yang belum pernah jadi host (murni klien) tidak punya `_db`
    // host — aman balikkan kosong, bukan crash null-check.
    if (_db == null) return const [];
    final rows = await _db!.listSyncUploadQueue();
    return rows.map(_pendingSyncItemFromRow).toList();
  }

  static PendingSyncItem _pendingSyncItemFromRow(SyncUploadQueueData row) {
    final rawTables = jsonDecode(row.tablesJson) as Map<String, dynamic>;
    final tables = rawTables.map((k, v) {
      final rows = (v as List).cast<Map<String, dynamic>>().map((r) {
        return r.map<String, Object?>((rk, rv) => MapEntry(rk, rv));
      }).toList();
      return MapEntry(k, rows);
    });
    return PendingSyncItem(
      id: row.id,
      fromIp: row.fromIp,
      arrivedAt: row.arrivedAt,
      tables: tables,
      since: row.since,
      tablesSummary: row.tablesSummary,
    );
  }

  // Item 40 — antrian usulan harga/produk (terpisah dari _pendingQueue).
  static final _pendingProposals = <PendingProductProposal>[];
  static void Function()? onProposalsChanged;

  static List<PendingProductProposal> get pendingProposals =>
      List.unmodifiable(_pendingProposals);

  /// Test-only seam: isi `_pendingProposals` tanpa perlu host/HTTP
  /// sungguhan (real socket dari beberapa test file berjalan konkuren di
  /// full-suite bisa saling tabrakan/hang di port sync yang sama).
  @visibleForTesting
  static void debugAddProposal(PendingProductProposal p) {
    _pendingProposals.add(p);
  }

  @visibleForTesting
  static void debugClearProposals() => _pendingProposals.clear();

  /// Buang usulan tanpa menerapkan apa pun — TIDAK ada tracking "ditolak"
  /// permanen: kalau device asal belum mengubah produk itu lagi, usulan
  /// yang sama akan otomatis muncul lagi di sync berikutnya (keputusan
  /// eksplisit: lebih baik owner ditanya ulang daripada usulan hilang
  /// diam-diam selamanya).
  static void dismissProposal(String id) {
    _pendingProposals.removeWhere((p) => p.id == id);
    onProposalsChanged?.call();
  }

  /// Terapkan produk yang disetujui (subset [approvedProductIds] dari
  /// usulan [id]) ke DB host, lalu buang usulan dari antrian.
  static Future<int> applyProposal(
      String id, Set<String> approvedProductIds) async {
    final idx = _pendingProposals.indexWhere((p) => p.id == id);
    if (idx < 0) return 0;
    final item = _pendingProposals.removeAt(idx);
    onProposalsChanged?.call();
    return _db!.applyProductProposals(item.rows, approvedProductIds);
  }

  /// Tabel append-only yang boleh diunggah klien ke host. Master data tidak
  /// pernah di-merge dari klien (alir satu arah host → bawahan).
  static const appendOnlyTables = {
    'transactions',
    'transaction_items',
    'transaction_payments',
    'stock_ledger',
    'loyalty_point_ledger',
    'expenses',
  };

  /// Item 41 B.3 — tabel yang boleh di-merge KLIEN dari respons host.
  /// Host sudah lama punya guard [appendOnlyTables]; klien dulu menerima
  /// nama tabel APA PUN dari respons (respons memang terenkripsi, tapi
  /// defense-in-depth murah: kalaupun ada yang bisa memanipulasi respons,
  /// merge tetap terkurung di daftar ini — bukan tabel arbitrer macam
  /// `app_settings`).
  static const clientMergeableTables = {
    ...appendOnlyTables,
    'products',
    'product_units',
    'price_tiers',
    'alt_prices',
    'product_barcodes',
    'product_group_tags',
    'customers',
    'customer_groups',
    'customer_group_prices',
    'kasir_permissions',
  };

  /// Kategori yang bisa dipilih owner saat menyetujui sync. Tabel transaksi
  /// digabung (header + item + pembayaran) agar tidak pernah terpisah.
  /// Tabel pertama tiap kategori dipakai untuk menghitung jumlah tampilan.
  static const syncCategories = <String, List<String>>{
    'Transaksi': ['transactions', 'transaction_items', 'transaction_payments'],
    'Stok': ['stock_ledger'],
    'Poin Loyalti': ['loyalty_point_ledger'],
    'Pengeluaran': ['expenses'],
  };

  // ─── Host (server) side ──────────────────────────────────────────────────

  /// Start shelf server. Returns (ip, token) pair.
  static Future<(String, String)> startHost({
    required AppDatabase db,
    required String storeKey,
  }) async {
    await stopHost();
    _db = db;
    _storeKey = storeKey;
    _syncToken = CryptoService.generateSyncToken();
    _failedAttempts.clear();
    _lockoutUntil.clear();

    final handler = const shelf.Pipeline().addHandler(_handleRequest);

    _server =
        await shelf_io.serve(handler, InternetAddress.anyIPv4, _kSyncPort);

    final ip = await detectHostIp();
    return (ip, _syncToken!);
  }

  /// Deteksi ulang IP host TANPA restart server — dipakai tombol "Refresh
  /// IP" di layar Sync WiFi. IP device bisa berubah SAAT server sudah jalan
  /// (lease DHCP baru, roaming antar-titik akses mesh WiFi, reconnect
  /// setelah layar mati lama) tanpa server itu sendiri ikut mati — QR/IP
  /// yang ditampilkan jadi basi kalau owner tidak pernah refresh manual.
  static Future<String> refreshHostIp() => detectHostIp();

  /// Deteksi IP LAN device ini. Strategi ganda:
  /// 1. `NetworkInfo.getWifiIP()` (API WiFi manager Android) — cara utama,
  ///    tapi TIDAK selalu bisa diandalkan di semua ROM/versi Android (bisa
  ///    balik null/basi di device tertentu).
  /// 2. Fallback: enumerasi `NetworkInterface.list()` langsung (dart:io,
  ///    TIDAK butuh izin tambahan apa pun) mencari alamat IPv4 privat
  ///    pertama — cara ini independen dari API WiFi manager sama sekali,
  ///    jadi tetap jalan walau strategi 1 gagal karena alasan platform.
  /// Kegagalan fallback dicatat ke [CrashLogService] (bukan dilempar) —
  /// murni utk membantu diagnosis laporan "kadang tidak tersambung" nanti,
  /// bukan fitur inti yang boleh menggagalkan start host.
  static Future<String> detectHostIp({
    Future<String?> Function()? getWifiIpOverride,
    Future<List<NetworkInterface>> Function()? listInterfacesOverride,
  }) async {
    try {
      final wifiIp = await (getWifiIpOverride ?? _defaultGetWifiIp)();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        return wifiIp;
      }
    } catch (e, st) {
      await CrashLogService.record(e, st, context: 'lan_sync_ip_wifi_api');
    }

    try {
      final interfaces =
          await (listInterfacesOverride ?? _defaultListInterfaces)();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (isPrivateIPv4(addr.address)) return addr.address;
        }
      }
    } catch (e, st) {
      await CrashLogService.record(e, st, context: 'lan_sync_ip_fallback');
    }

    await CrashLogService.record(
        'Gagal deteksi IP LAN via kedua strategi (WiFi API & NetworkInterface)',
        null,
        context: 'lan_sync_ip_detect_failed');
    return 'Unknown IP';
  }

  static Future<String?> _defaultGetWifiIp() => NetworkInfo().getWifiIP();

  static Future<List<NetworkInterface>> _defaultListInterfaces() =>
      NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);

  /// true bila [ip] termasuk rentang IPv4 privat (RFC 1918) — dipakai
  /// filter kandidat IP LAN dari [detectHostIp]. Public & pure (mudah
  /// diuji tanpa I/O nyata).
  static bool isPrivateIPv4(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return false;
    final a = parts[0]!, b = parts[1]!;
    if (a < 0 || a > 255 || b < 0 || b > 255) return false;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }

  /// Buang baris append-only yang tanggalnya jatuh di tahun yang SUDAH
  /// ditutup-buku host ([archivedYears] = tahun-tahun yang benar-benar punya
  /// file arsip, dari `TutupBukuService.listArchivedYears`).
  ///
  /// Tanpa filter ini, upload klien yang selalu full-dump sejak epoch akan
  /// meng-insert ULANG transaksi tahun terarsip: tutup buku menghapus baris
  /// aslinya dari DB utama, sehingga `INSERT OR IGNORE` tidak menemukan PK
  /// lama dan data "hidup lagi" — dobel dengan arsip, ringkasan harian tahun
  /// lama ikut terbangun kembali, dan file DB membengkak lagi.
  ///
  /// SENGAJA per-tahun-arsip (bukan cutoff `last_archive_year`): UI tutup
  /// buku hanya bisa mengarsipkan "tahun lalu", jadi toko yang baru mulai
  /// tutup buku bisa punya tahun-tahun lebih lama yang TIDAK pernah diarsip
  /// dan datanya masih sah di DB utama — baris klien dari tahun-tahun itu
  /// harus tetap boleh masuk (dedup PK sudah ditangani INSERT OR IGNORE).
  ///
  /// Aturan:
  ///  • `transactions`, `stock_ledger`, `loyalty_point_ledger`, `expenses`
  ///    dengan `created_at` di tahun terarsip → dibuang.
  ///  • `transaction_items` / `transaction_payments` dibuang bila transaksi
  ///    induknya ikut terbuang ATAU tidak ada sama sekali (tidak di payload
  ///    dan tidak di DB lokal) — mencegah pelanggaran FK saat merge.
  static Future<Map<String, List<Map<String, Object?>>>> filterArchivedRows(
      AppDatabase db,
      Map<String, List<Map<String, Object?>>> tables,
      Set<int> archivedYears) async {
    if (archivedYears.isEmpty) return tables;

    bool inArchivedYear(Object? createdAt) =>
        createdAt is int &&
        archivedYears.contains(
            DateTime.fromMillisecondsSinceEpoch(createdAt * 1000).year);

    final out = <String, List<Map<String, Object?>>>{};
    final keptTxIds = <Object?>{};
    final droppedTxIds = <Object?>{};

    // 1. Header transaksi dulu — hasilnya menentukan nasib child rows.
    final txRows = tables['transactions'];
    if (txRows != null) {
      final kept = <Map<String, Object?>>[];
      for (final r in txRows) {
        if (inArchivedYear(r['created_at'])) {
          droppedTxIds.add(r['id']);
        } else {
          kept.add(r);
          keptTxIds.add(r['id']);
        }
      }
      out['transactions'] = kept;
    }

    // 2. Child rows: cek induk yang tidak dikenal ke DB lokal (chunked).
    const childTables = ['transaction_items', 'transaction_payments'];
    final unknownParents = <String>{};
    for (final t in childTables) {
      for (final r in tables[t] ?? const <Map<String, Object?>>[]) {
        final pid = r['transaction_id'];
        if (pid is String &&
            !keptTxIds.contains(pid) &&
            !droppedTxIds.contains(pid)) {
          unknownParents.add(pid);
        }
      }
    }
    final existingParents = <String>{};
    final unknownList = unknownParents.toList();
    for (var i = 0; i < unknownList.length; i += 500) {
      final chunk =
          unknownList.sublist(i, (i + 500).clamp(0, unknownList.length));
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await db.customSelect(
        'SELECT id FROM transactions WHERE id IN ($placeholders)',
        variables: [for (final id in chunk) Variable.withString(id)],
      ).get();
      for (final r in rows) {
        existingParents.add(r.data['id'] as String);
      }
    }
    for (final t in childTables) {
      final rows = tables[t];
      if (rows == null) continue;
      out[t] = [
        for (final r in rows)
          if (r['transaction_id'] is String &&
              (keptTxIds.contains(r['transaction_id']) ||
                  existingParents.contains(r['transaction_id'])))
            r,
      ];
    }

    // 3. Tabel append-only lain: cukup filter created_at.
    for (final entry in tables.entries) {
      if (entry.key == 'transactions' || childTables.contains(entry.key)) {
        continue;
      }
      if (entry.key == 'stock_ledger' ||
          entry.key == 'loyalty_point_ledger' ||
          entry.key == 'expenses') {
        out[entry.key] = [
          for (final r in entry.value)
            if (!inArchivedYear(r['created_at'])) r,
        ];
      } else {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  /// Setujui item antrian → merge data ke DB, kirim balik data host.
  ///
  /// [allowedTables] (opsional) membatasi tabel mana yang di-merge — dipakai
  /// owner untuk memilih kategori data yang diterima. Bila null, semua tabel
  /// append-only diterima. Master data dari klien tidak pernah di-merge.
  static Future<int> approveSync(String itemId,
      {Set<String>? allowedTables}) async {
    final row = await _db!.getSyncUploadQueueItem(itemId);
    if (row == null) return 0;
    final item = _pendingSyncItemFromRow(row);

    // Saring data dari tahun yang sudah ditutup-buku SEBELUM merge — lihat
    // dok [filterArchivedRows].
    final archivedYears = (await TutupBukuService.listArchivedYears()).toSet();
    final tables = await filterArchivedRows(_db!, item.tables, archivedYears);

    int received = 0;
    final touchedTxIds = <String>{};
    final touchedStockUnitIds = <String>{};
    for (final entry in tables.entries) {
      // Guard satu arah: hanya tabel append-only yang boleh dari klien.
      if (!appendOnlyTables.contains(entry.key)) continue;
      // Filter kategori yang dipilih owner.
      if (allowedTables != null && !allowedTables.contains(entry.key)) continue;
      received += await _db!.mergeRows(entry.key, entry.value, true);
      _collectTxIds(entry.key, entry.value, touchedTxIds);
      _collectStockUnitIds(entry.key, entry.value, touchedStockUnitIds);
    }
    // Rekonsiliasi total/paid dari child rows sebelum membangun ringkasan.
    // Id diambil juga dari item/pembayaran, sehingga transaksi lama yang hanya
    // menerima cicilan / item susulan via sync ikut dikoreksi headernya.
    await _db!.reconcileTransactionsByIds(touchedTxIds);
    await _db!.rebuildSummariesForTxIds(touchedTxIds);
    // Item 41 A.1 — saldo stok WAJIB dihitung ulang setelah merge: baris
    // ledger dari device lain membawa `stock_after` hasil hitungan saldo
    // LOKAL device itu (bisa beda dari saldo di sini) — tanpa rebuild,
    // baris "terbaru" milik device lain menimpa pandangan saldo host
    // secara diam-diam (lihat rebuildStockAfterForUnits).
    await _db!.rebuildStockAfterForUnits(touchedStockUnitIds);
    // Item 17 Fase 2 — item ini SUDAH resmi diproses, hapus dari antrian
    // durable (bukan cuma dari tampilan) supaya tidak pernah diproses ulang
    // walau host restart.
    await _db!.deleteSyncUploadQueueItem(itemId);
    onQueueChanged?.call();
    return received;
  }

  /// Kumpulkan id transaksi yang disentuh sebuah payload sync: dari header
  /// (`transactions.id`) maupun child rows (`transaction_id` pada item &
  /// pembayaran) — untuk rekonsiliasi dan refresh ringkasan harian.
  static void _collectTxIds(
      String table, List<Map<String, Object?>> rows, Set<String> out) {
    final key = table == 'transactions'
        ? 'id'
        : (table == 'transaction_items' || table == 'transaction_payments')
            ? 'transaction_id'
            : null;
    if (key == null) return;
    for (final r in rows) {
      final id = r[key];
      if (id is String && id.isNotEmpty) out.add(id);
    }
  }

  /// Kumpulkan product_unit_id dari baris `stock_ledger` sebuah payload —
  /// untuk [AppDatabase.rebuildStockAfterForUnits] setelah merge (Item 41
  /// A.1). Ledger selalu ditulis pada satuan DASAR (di device asal), jadi
  /// id di sini sudah id satuan dasar.
  static void _collectStockUnitIds(
      String table, List<Map<String, Object?>> rows, Set<String> out) {
    if (table != 'stock_ledger') return;
    for (final r in rows) {
      final uid = r['product_unit_id'];
      if (uid is String && uid.isNotEmpty) out.add(uid);
    }
  }

  /// Tolak item antrian tanpa merge. Item 17 Fase 2 — KEPUTUSAN DESAIN:
  /// tolak sekarang PERMANEN (dulu klien selalu full-dump sejak epoch, jadi
  /// data yang ditolak otomatis "muncul lagi" di sync berikutnya — dengan
  /// watermark upload delta-only, itu tidak lagi terjadi: sekali data
  /// sampai & tersimpan durable di sini, urusan klien SELESAI terlepas dari
  /// keputusan owner). UI WAJIB minta konfirmasi eksplisit sebelum memanggil
  /// ini (lihat `sync_screen.dart`) — tidak ada jalan otomatis utk
  /// memunculkannya lagi, HANYA lewat "Sync Ulang Penuh" (`resetUploadWatermark`)
  /// di sisi klien.
  static Future<void> rejectSync(String itemId) async {
    await _db!.deleteSyncUploadQueueItem(itemId);
    onQueueChanged?.call();
  }

  static Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    _syncToken = null;
    _failedAttempts.clear();
    _lockoutUntil.clear();
    _usedNonces.clear();
    debugHostRunningOverride = false;
  }

  /// Item 21 — seam test-only: `testWidgets` + `HttpServer` sungguhan
  /// terbukti bikin `AppDatabase.close()` HANG tanpa batas (lihat catatan
  /// `sync_screen_timeout_ip_test.dart`/HANDOFF) — test widget yang cuma
  /// perlu observasi `isHostRunning=true` (mis. provider/banner persisten)
  /// pakai ini, BUKAN `startHost()` sungguhan. Selalu false di produksi.
  @visibleForTesting
  static bool debugHostRunningOverride = false;

  static bool get isHostRunning =>
      _server != null || debugHostRunningOverride;

  static Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.method != 'POST' || request.url.path != 'sync') {
      return shelf.Response.notFound('Not found');
    }

    final ip =
        (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'unknown';

    // Rate-limiting: check lockout before reading body. Entri yang sudah
    // kedaluwarsa dibuang sekalian (Item 41 B.6) — tanpa ini map tumbuh
    // terus selama sesi host panjang (satu entri per IP yang pernah gagal).
    final nowForLockout = DateTime.now();
    _lockoutUntil.removeWhere((_, until) => !until.isAfter(nowForLockout));
    final lockedUntil = _lockoutUntil[ip];
    if (lockedUntil != null) {
      return shelf.Response(429, body: 'Too many attempts. Try again later.');
    }

    // Reject oversized payloads before buffering (DoS protection).
    final declaredLength =
        int.tryParse(request.headers['content-length'] ?? '') ?? 0;
    if (declaredLength > _kMaxPayloadBytes) {
      return shelf.Response(413, body: 'Payload too large');
    }

    try {
      // Defense-in-depth: kalau koneksi klien berhenti mengirim di tengah
      // jalan (mis. klien crash/app dibunuh OS saat transfer), jangan
      // gantung handler ini selamanya — request lain masih bisa diproses
      // shelf secara paralel, tapi tetap baik untuk membatasi resource yg
      // nyangkut. Titik infinite-loading yang dilaporkan user ada di sisi
      // KLIEN (syncToHost), ini cuma pengaman tambahan di sisi host.
      // `.timeout()` WAJIB di atas Stream (sebelum dikumpulkan) — timeout
      // PER-EVENT/idle, bukan deadline total, supaya upload besar yang
      // sedang aktif mengalir tidak diputus paksa (lihat catatan sama di
      // syncToHost).
      //
      // Item 41 A.4 — kumpulkan via BytesBuilder per-CHUNK, bukan
      // `.expand().toList()` per-BYTE: List<int> growable menyimpan tiap
      // byte sbg elemen 8-byte (payload 50 MB ≈ 400 MB list) — di HP RAM
      // 1-2 GB itu OOM nyata. BytesBuilder(copy:false) menahan chunk asli
      // lalu digabung sekali di takeBytes() (~1x ukuran payload).
      final bodyBuilder = BytesBuilder(copy: false);
      await request
          .read()
          .timeout(const Duration(seconds: 30))
          .forEach(bodyBuilder.add);
      if (bodyBuilder.length > _kMaxPayloadBytes) {
        return shelf.Response(413, body: 'Payload too large');
      }
      final bodyBytes = bodyBuilder.takeBytes();

      final token = request.headers['x-sync-token'] ?? '';
      if (!_constantTimeEqual(token, _syncToken ?? '')) {
        _failedAttempts[ip] = (_failedAttempts[ip] ?? 0) + 1;
        if ((_failedAttempts[ip] ?? 0) >= _kMaxFailures) {
          _lockoutUntil[ip] = DateTime.now().add(_kLockoutDuration);
          _failedAttempts.remove(ip);
        }
        return shelf.Response.forbidden('Invalid token');
      }
      _failedAttempts.remove(ip);

      // B-3: Validasi HMAC + nonce (anti-tamper + anti-replay).
      final nonce = request.headers['x-sync-nonce'] ?? '';
      final tsStr = request.headers['x-sync-ts'] ?? '';
      final clientHmac = request.headers['x-sync-hmac'] ?? '';

      if (nonce.isEmpty || tsStr.isEmpty || clientHmac.isEmpty) {
        return shelf.Response(400, body: 'Missing HMAC headers');
      }
      // Tolak timestamp lebih dari 5 menit dari sekarang. Pesan harus bisa
      // dimengerti pemilik toko — penyebab tersering adalah jam salah satu
      // HP meleset (device offline sering tidak sinkron waktu otomatis).
      final ts = DateTime.tryParse(tsStr);
      if (ts == null ||
          DateTime.now().difference(ts).abs() > const Duration(minutes: 5)) {
        return shelf.Response(400,
            body: 'Jam perangkat berbeda lebih dari 5 menit dari perangkat '
                'ini. Samakan tanggal & jam kedua HP (aktifkan "tanggal & '
                'waktu otomatis"), lalu coba sync lagi.');
      }
      // Tolak nonce yang sudah pernah dipakai (replay prevention).
      if (_usedNonces.contains(nonce)) {
        return shelf.Response(400, body: 'Nonce replayed');
      }
      // Batasi ukuran cache nonce (sesi host yang lama sekali bisa menumpuk).
      // Set Dart menjaga urutan sisip → buang yang paling lama.
      while (_usedNonces.length >= 5000) {
        _usedNonces.remove(_usedNonces.first);
      }
      // Item 41 A.4 — base64 payload dihitung SEKALI lalu dipakai dua kali
      // (HMAC & decrypt); sebelumnya di-encode 2x (~1,33x payload per
      // encode). CATATAN protokol: input HMAC memang atas string base64
      // (bukan bytes mentah) — JANGAN diubah, klien versi lama menghitung
      // dgn format ini; mengganti format = sync lintas versi app mendadak
      // gagal "HMAC mismatch" tanpa pesan yang bisa dimengerti user.
      final bodyB64 = base64Encode(bodyBytes);
      final hmacKey = CryptoService.deriveSyncHmacKey(_storeKey!, _syncToken!);
      final expectedHmac = CryptoService.hmacSha256(
        utf8.encode('$nonce:$tsStr:$bodyB64'),
        hmacKey,
      );
      if (!_constantTimeEqual(clientHmac, _hexOf(expectedHmac))) {
        return shelf.Response.forbidden('HMAC mismatch');
      }
      _usedNonces.add(nonce);

      final key = CryptoService.deriveSyncKey(_storeKey!, _syncToken!);
      final payloadJson =
          CryptoService.decryptText(bodyB64, Uint8List.fromList(key));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

      final sinceStr = payload['since'] as String?;
      final since = sinceStr != null
          ? DateTime.parse(sinceStr)
          : DateTime.fromMillisecondsSinceEpoch(0);

      // B-4: Queue incoming tables for owner approval instead of auto-merging.
      final rawTables = payload['tables'] as Map<String, dynamic>? ?? {};
      final tables = rawTables.map((k, v) {
        final rows = (v as List).cast<Map<String, dynamic>>().map((r) {
          return r.map<String, Object?>((rk, rv) => MapEntry(rk, rv));
        }).toList();
        return MapEntry(k, rows);
      });

      // Build a human-readable summary for the approval UI.
      final parts = <String>[];
      for (final e in tables.entries) {
        if (e.value.isNotEmpty) {
          final label = _tableLabel(e.key);
          parts.add('${e.value.length} $label');
        }
      }
      final summary = parts.isEmpty ? 'tidak ada data baru' : parts.join(', ');

      // Item 17 Fase 2 — simpan DURABLE ke DB SEBELUM host membalas ke
      // klien di bawah. Urutan ini KRUSIAL: respons 200 ber-HMAC yang
      // klien terima adalah SATU-SATUNYA sinyal "aman majukan watermark
      // upload" (lihat dok `_kUploadWatermarkKey` di `syncToHost`) — kalau
      // insert ini gagal/exception, klien tidak akan pernah menerima
      // respons sukses, jadi watermark-nya TIDAK maju & akan otomatis
      // kirim ulang di percobaan berikutnya (aman, tidak ada data hilang).
      // "1 slot per IP" (Item 41 A.3, cegah RAM menumpuk saat klien
      // nge-sync berulang sebelum owner approve) dipertahankan di dalam
      // `enqueueSyncUpload` (delete+insert 1 transaksi) — AMAN menimpa item
      // lama krn payload klien per-sync selalu superset dari watermark
      // upload klien saat itu.
      final itemId = _generateNonce();
      await _db!.enqueueSyncUpload(
        id: itemId,
        fromIp: ip,
        tablesJson: jsonEncode(tables),
        since: since,
        tablesSummary: summary,
      );
      onQueueChanged?.call();

      // Item 40 — usulan harga/produk, antrian TERPISAH dari _pendingQueue
      // (lihat dok PendingProductProposal soal alasan dipisah).
      final rawProposals =
          payload['proposals'] as Map<String, dynamic>? ?? {};
      final proposalRows = rawProposals.map((k, v) {
        final rows = (v as List).cast<Map<String, dynamic>>().map((r) {
          return r.map<String, Object?>((rk, rv) => MapEntry(rk, rv));
        }).toList();
        return MapEntry(k, rows);
      });
      var proposedProducts = proposalRows['products'] ?? const [];
      var filteredProposalRows = proposalRows;
      if (proposedProducts.isNotEmpty) {
        // Buang produk yang isinya SUDAH IDENTIK dgn data owner saat ini —
        // laporan nyata user: produk yang flag `locally_modified` klien-nya
        // macet true terus-menerus diusulkan ulang tiap sync walau tidak
        // ada apa pun yang perlu diputuskan. Lihat dok
        // `AppDatabase.filterUnchangedProposals`.
        filteredProposalRows =
            await _db!.filterUnchangedProposals(proposalRows);
        proposedProducts = filteredProposalRows['products'] ?? const [];
      }
      if (proposedProducts.isNotEmpty) {
        // Item 41 A.3 — sama seperti _pendingQueue: satu slot per IP.
        // dumpLocalProposals juga selalu paket penuh (semua produk ber-flag
        // locallyModified), jadi usulan terbaru superset dari yang lama.
        _pendingProposals.removeWhere((p) => p.fromIp == ip);
        _pendingProposals.add(PendingProductProposal(
          id: _generateNonce(),
          fromIp: ip,
          arrivedAt: DateTime.now(),
          rows: filteredProposalRows,
          productCount: proposedProducts.length,
        ));
        onProposalsChanged?.call();
      } else if (_pendingProposals.any((p) => p.fromIp == ip)) {
        // Semua produk yang tadinya diusulkan device ini sekarang sudah
        // identik dgn data owner — usulan lama (kalau ada) sudah basi juga,
        // bersihkan supaya tidak nyangkut di antrian.
        _pendingProposals.removeWhere((p) => p.fromIp == ip);
        onProposalsChanged?.call();
      }

      // Immediately send back the host's data since the client's timestamp.
      // The client receives host updates even before their data is approved.
      final outDump = await _db!.dumpSince(since);
      final outPayload = {
        'tables': outDump,
        // Item 41 A.2 — selalu UTC (lihat catatan zona waktu di syncToHost).
        'since': DateTime.now().toUtc().toIso8601String(),
        'pendingId': itemId,
        'status': 'pending_approval',
      };
      final outJson = jsonEncode(outPayload);
      final encrypted =
          CryptoService.encryptText(outJson, Uint8List.fromList(key));

      // Item 41 B.2 — respons juga di-HMAC (dulu hanya arah request):
      // tanpa ini, MITM aktif di LAN bisa men-tamper/replay respons host
      // (CBC tanpa MAC itu malleable). Klien versi lama mengabaikan header
      // tambahan ini (kompatibel mundur), klien baru memverifikasi bila ada.
      final respNonce = _generateNonce();
      final respTs = DateTime.now().toUtc().toIso8601String();
      final respHmac = _hexOf(CryptoService.hmacSha256(
        utf8.encode('$respNonce:$respTs:$encrypted'),
        hmacKey,
      ));

      return shelf.Response.ok(
        base64Decode(encrypted),
        headers: {
          'content-type': 'application/octet-stream',
          'x-sync-nonce': respNonce,
          'x-sync-ts': respTs,
          'x-sync-hmac': respHmac,
        },
      );
    } catch (e, st) {
      // Log utk diagnosis laporan "kadang tidak tersambung" — request yang
      // sampai sini SUDAH lolos rate-limit/token, jadi gagalnya di tahap
      // decrypt/parse/merge, bukan masalah jaringan (itu domain klien).
      await CrashLogService.record(e, st, context: 'lan_sync_host_request');
      return shelf.Response.internalServerError(body: 'Sync failed');
    }
  }

  static const _kTableLabels = {
    'transactions': 'transaksi',
    'transaction_items': 'item transaksi',
    'transaction_payments': 'pembayaran',
    'stock_ledger': 'stok',
    'loyalty_point_ledger': 'poin loyalti',
    'expenses': 'pengeluaran',
    'products': 'produk',
    'product_units': 'satuan',
    'price_tiers': 'harga',
    'alt_prices': 'harga alternatif',
    'product_barcodes': 'barcode',
    'product_group_tags': 'tag kategori',
    'customers': 'pelanggan',
    'customer_groups': 'grup pelanggan',
    'customer_group_prices': 'harga grup',
    'kasir_permissions': 'izin kasir',
  };

  static String _tableLabel(String tableName) =>
      _kTableLabels[tableName] ?? tableName;

  /// Representasi hex lowercase dari bytes (dipakai HMAC request & respons).
  static String _hexOf(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Constant-time string comparison — prevents timing side-channel on token.
  static bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  // ─── Client side ─────────────────────────────────────────────────────────

  /// Key `app_settings` untuk watermark "sampai kapan data HOST terakhir kali
  /// berhasil diterima & di-merge ke DB lokal". HANYA untuk arah host→klien.
  static const _kDownloadWatermarkKey = 'last_sync_download_at';

  static Future<DateTime?> _loadDownloadWatermark(AppDatabase db) async {
    final raw = await db.getSetting(_kDownloadWatermarkKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // Item 41 A.2 — simpan UTC eksplisit ('Z') supaya tidak ditafsirkan ulang
  // pada zona waktu berbeda (mis. user pindah zona / ganti setelan jam).
  static Future<void> _saveDownloadWatermark(AppDatabase db, DateTime at) =>
      db.setSetting(_kDownloadWatermarkKey, at.toUtc().toIso8601String());

  /// Item 17 Fase 2 — watermark arah klien→host (dulu SENGAJA selalu
  /// epoch/full-dump, lihat histori di commit sebelumnya: alasannya waktu
  /// itu antrian approval host cuma di RAM, jadi data yang "hilang" dari
  /// antrian sebelum owner approve tidak akan pernah terkirim ulang kalau
  /// watermark dimajukan begitu saja). Sekarang AMAN dimajukan karena
  /// `_handleRequest` di sisi host menyimpan upload ke `sync_upload_queue`
  /// (tabel DB, bukan RAM) SEBELUM membalas — respons 200 ber-HMAC yang
  /// berhasil diverifikasi klien di sini SUDAH cukup jadi bukti "host sudah
  /// simpan durable", terlepas dari kapan/apakah owner nanti approve/tolak.
  static const _kUploadWatermarkKey = 'last_sync_upload_confirmed_at';

  static Future<DateTime?> _loadUploadWatermark(AppDatabase db) async {
    final raw = await db.getSetting(_kUploadWatermarkKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> _saveUploadWatermark(AppDatabase db, DateTime at) =>
      db.setSetting(_kUploadWatermarkKey, at.toUtc().toIso8601String());

  /// "Sync Ulang Penuh" — escape hatch manual (Pengaturan) utk memaksa
  /// upload full-dump lagi sejak epoch di sync berikutnya. Dipakai kalau
  /// owner salah tolak (tolak sekarang PERMANEN, lihat dok [rejectSync])
  /// atau curiga ada data yang tidak pernah sampai ke host.
  static Future<void> resetUploadWatermark(AppDatabase db) =>
      // String kosong (bukan hapus baris) — `_loadUploadWatermark` sudah
      // menangani ini via `DateTime.tryParse('')` → null → fallback epoch,
      // tanpa perlu method delete-setting baru.
      db.setSetting(_kUploadWatermarkKey, '');

  static Future<SyncResult> syncToHost({
    required AppDatabase db,
    required String storeKey,
    required String hostIp,
    required String syncToken,
    DateTime? since,
    // Dapat dipersingkat di test (mis. simulasi host yang tidak pernah
    // membalas) tanpa memperlambat suite dgn menunggu timeout produksi.
    // `responseTimeout` dipakai utk 2 hal: (1) deadline TOTAL menunggu host
    // mulai membalas (host perlu waktu susun+enkripsi SELURUH dump SEBELUM
    // kirim byte pertama, bisa lama utk toko data besar), dan (2) idle-
    // timeout PER-CHUNK saat membaca body (reset tiap ada data baru lewat —
    // lihat catatan di titik pemakaiannya, JANGAN diterapkan sbg deadline
    // total di sana, toko data besar bisa transfer >20s scr wajar).
    Duration connectTimeout = const Duration(seconds: 10),
    Duration responseTimeout = const Duration(seconds: 30),
  }) async {
    final key = CryptoService.deriveSyncKey(storeKey, syncToken);
    // Watermark host→klien: kalau caller tidak beri `since` eksplisit, pakai
    // watermark tersimpan dari sync sukses terakhir (bukan selalu epoch) —
    // supaya host tidak perlu dump SELURUH riwayat toko tiap kali ada satu
    // kasir sync. Dicatat SEBELUM request dikirim, supaya data host yang
    // berubah SELAMA sync ini berlangsung tidak "terlewat" di sync
    // berikutnya (lebih baik terima sedikit dobel yang aman di-merge ulang,
    // daripada kehilangan data).
    // Item 41 A.2 — SEMUA timestamp protokol sync WAJIB UTC eksplisit
    // (suffix 'Z'). `toIso8601String()` waktu LOKAL tidak membawa offset,
    // dan `DateTime.parse` di sisi seberang menafsirkannya pada zona waktu
    // device SANA — dua HP beda zona (WIB/WITA/WIT itu nyata, atau salah
    // setel zona) membuat host melewatkan data hingga selisih jamnya
    // secara diam-diam.
    final downloadSince = since ??
        await _loadDownloadWatermark(db) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final downloadSyncStartedAt = DateTime.now().toUtc();

    // Item 17 Fase 2 — watermark upload (dicatat SEBELUM outDump disusun,
    // pola sama dgn downloadSyncStartedAt: data lokal yang berubah SELAMA
    // sync ini berlangsung tidak boleh "terlewat" di sync berikutnya).
    final uploadSince = await _loadUploadWatermark(db) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final uploadSyncStartedAt = DateTime.now().toUtc();

    // Klien (perangkat bawahan) hanya mengirim data append-only ke atas.
    // Master data (produk, harga, izin) tidak diunggah agar tidak menimpa
    // data owner — master data mengalir satu arah dari host ke bawah.
    final outDump =
        await db.dumpSince(uploadSince, includeMasterData: false);
    // Item 40 — usulan harga/produk (device non-owner) SELALU ikut terkirim
    // apa adanya (bukan lewat jalur merge master data biasa) — owner review
    // manual lewat antrian TERPISAH (lihat PendingProductProposal). Kosong
    // (`{}`) di device owner (tidak pernah menandai produknya sendiri).
    final proposals = await db.dumpLocalProposals();
    final payload = {
      // Item 41 A.2 — UTC eksplisit, lihat catatan di atas.
      'since': downloadSince.toUtc().toIso8601String(),
      'tables': outDump,
      'proposals': proposals,
    };
    final payloadJson = jsonEncode(payload);
    final encrypted =
        CryptoService.encryptText(payloadJson, Uint8List.fromList(key));
    final encryptedBytes = base64Decode(encrypted);

    // B-3: Tambah nonce + timestamp + HMAC ke setiap request.
    // Item 41 A.4 — `encrypted` SUDAH string base64 payload; pakai ulang utk
    // input HMAC (dulu di-base64Encode ULANG dari bytes — salinan ~1,33x
    // payload yang tidak perlu). Format input HMAC tetap sama persis.
    final nonce = _generateNonce();
    final tsStr = DateTime.now().toUtc().toIso8601String();
    final hmacKey = CryptoService.deriveSyncHmacKey(storeKey, syncToken);
    final hmac = CryptoService.hmacSha256(
      utf8.encode('$nonce:$tsStr:$encrypted'),
      hmacKey,
    );
    final hmacHex = _hexOf(hmac);

    // B-5: tanpa timeout, request yang hang (mis. IP host sudah tidak valid,
    // AP client isolation di WiFi diam-diam membuang paket, atau host sempat
    // freeze) bikin _sync() di UI klien LOADING SELAMANYA — tidak pernah
    // sukses ATAUPUN gagal, jadi owner juga tidak pernah lihat konfirmasi
    // apa pun (klien-nya sendiri tidak pernah selesai memproses). Timeout di
    // sini memastikan syncToHost SELALU akhirnya throw kalau jaringan
    // bermasalah, supaya UI bisa tampilkan pesan error & berhenti spinning.
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final HttpClientResponse response;
      final List<int> respBytes;
      try {
        final request = await client
            .post(hostIp, _kSyncPort, 'sync')
            .timeout(connectTimeout);
        request.headers.set('x-sync-token', syncToken);
        request.headers.set('x-sync-nonce', nonce);
        request.headers.set('x-sync-ts', tsStr);
        request.headers.set('x-sync-hmac', hmacHex);
        request.headers.set('content-type', 'application/octet-stream');
        request.add(encryptedBytes);
        response = await request.close().timeout(responseTimeout);
        // PENTING: `.timeout()` di sini WAJIB dipasang SEBELUM `.toList()`
        // (di atas Stream<int>, bukan di atas Future<List<int>> hasil
        // toList()) — Stream.timeout() itu timeout PER-EVENT (reset tiap ada
        // chunk baru lewat), sedangkan Future.timeout() adalah deadline
        // TOTAL yang tidak peduli progres. Toko dengan data besar (banyak
        // produk/transaksi, terutama sync pertama kali yang full-dump) bisa
        // transfer >20 detik SECARA WAJAR selama datanya terus mengalir —
        // pola lama (`.toList().timeout(...)`) memutus transfer itu di
        // tengah jalan padahal sedang aktif menerima data, bukan macet.
        // Item 41 A.4 — BytesBuilder per-chunk, bukan .expand().toList()
        // per-byte (alasan memori sama dgn sisi host, lihat _handleRequest).
        final respBuilder = BytesBuilder(copy: false);
        await response.timeout(responseTimeout).forEach(respBuilder.add);
        respBytes = respBuilder.takeBytes();
      } on TimeoutException catch (e, st) {
        await CrashLogService.record(e, st,
            context: 'lan_sync_client_timeout hostIp=$hostIp '
                'connectTimeout=$connectTimeout responseTimeout=$responseTimeout');
        throw Exception(
            'Tidak ada respons dari host dalam waktu wajar. Kemungkinan '
            'penyebab: (1) router memblokir koneksi antar-HP walau satu '
            'WiFi (fitur "isolasi klien"), (2) HP owner mengunci layar/'
            'pindah app lain sehingga koneksi latar belakang dimatikan '
            'sistem, atau (3) data toko sangat besar & butuh waktu lebih '
            'lama — coba naikkan profil timeout di bawah. Pastikan juga '
            'IP/Token host masih berlaku (mulai ulang server di HP owner '
            'lalu scan ulang).');
      } on SocketException catch (e, st) {
        await CrashLogService.record(e, st,
            context: 'lan_sync_client_socket hostIp=$hostIp');
        final msg = e.message.toLowerCase();
        final hint = msg.contains('unreachable')
            ? ' Kemungkinan HP ini sedang pakai jalur data seluler, bukan '
                'WiFi, utk koneksi ke perangkat lain — coba matikan data '
                'seluler sementara lalu sync ulang.'
            : msg.contains('refused') || msg.contains('no route')
                ? ' Kemungkinan IP sudah tidak sesuai (device owner ganti '
                    'jaringan/restart) atau router mengisolasi koneksi '
                    'antar-HP — minta owner refresh IP & bagikan ulang QR.'
                : '';
        throw Exception(
            'Tidak bisa terhubung ke host ($hostIp): ${e.message}.$hint '
            'Pastikan kedua perangkat terhubung ke WiFi yang sama & IP '
            'masih benar.');
      }

      if (response.statusCode != 200) {
        final body = utf8.decode(respBytes);
        throw Exception('Server error ${response.statusCode}: $body');
      }

      final respB64 = base64Encode(respBytes);

      // Item 41 B.2 — verifikasi HMAC respons BILA host mengirim headernya
      // (host versi baru selalu kirim). Host versi lama tidak mengirim →
      // dilewati demi kompatibilitas mundur; konsekuensinya MITM aktif bisa
      // "menelanjangi" header utk memaksa jalur tanpa-verifikasi (downgrade)
      // — diterima sadar utk masa transisi, tetap jauh lebih baik daripada
      // tidak pernah verifikasi sama sekali.
      final respHmacHeader = response.headers.value('x-sync-hmac');
      if (respHmacHeader != null) {
        final respNonce = response.headers.value('x-sync-nonce') ?? '';
        final respTs = response.headers.value('x-sync-ts') ?? '';
        final hmacKey = CryptoService.deriveSyncHmacKey(storeKey, syncToken);
        final expected = _hexOf(CryptoService.hmacSha256(
          utf8.encode('$respNonce:$respTs:$respB64'),
          hmacKey,
        ));
        if (!_constantTimeEqual(respHmacHeader, expected)) {
          throw Exception(
              'Respons host tidak lolos verifikasi keamanan (HMAC). Data '
              'TIDAK di-merge. Coba sync ulang; kalau terus terjadi, mulai '
              'ulang server di HP owner lalu scan ulang QR.');
        }
      }

      final respJson =
          CryptoService.decryptText(respB64, Uint8List.fromList(key));
      final respPayload = jsonDecode(respJson) as Map<String, dynamic>;

      int received = 0;
      final tables = respPayload['tables'] as Map<String, dynamic>? ?? {};
      final touchedTxIds = <String>{};
      final touchedStockUnitIds = <String>{};
      for (final entry in tables.entries) {
        // Item 41 B.3 — hanya tabel yang memang disinkronkan (allowlist);
        // nama tak dikenal dilewati, bukan diteruskan mentah ke merge.
        if (!clientMergeableTables.contains(entry.key)) continue;
        final rows =
            (entry.value as List).cast<Map<String, dynamic>>().map((r) {
          return r.map<String, Object?>((k, v) => MapEntry(k, v));
        }).toList();
        // Klien menerima data dari host: master data di-merge last-write-wins
        // (data owner menang), append-only di-INSERT OR IGNORE.
        received += await db.mergeRows(
            entry.key, rows, appendOnlyTables.contains(entry.key));
        _collectTxIds(entry.key, rows, touchedTxIds);
        _collectStockUnitIds(entry.key, rows, touchedStockUnitIds);
      }
      // Rekonsiliasi total/paid dari child rows, lalu refresh ringkasan harian
      // untuk tanggal yang tersentuh — termasuk transaksi lama yang hanya
      // menerima cicilan / item susulan (headernya tidak ada di payload).
      await db.reconcileTransactionsByIds(touchedTxIds);
      await db.rebuildSummariesForTxIds(touchedTxIds);
      // Item 41 A.1 — hitung ulang saldo stok utk unit yang tersentuh merge
      // (alasan sama dgn approveSync di sisi host).
      await db.rebuildStockAfterForUnits(touchedStockUnitIds);

      // Watermark HANYA disimpan setelah data host benar-benar ter-merge
      // permanen ke DB lokal (baris di atas ini) — kalau ada exception di
      // langkah mana pun sebelum sini, watermark TIDAK maju, jadi sync
      // berikutnya otomatis retry dari titik lama (aman, cuma kirim/terima
      // agak lebih banyak, bukan kehilangan data).
      await _saveDownloadWatermark(db, downloadSyncStartedAt);
      // Item 17 Fase 2 — watermark upload HANYA dimajukan setelah sampai
      // titik ini: respons 200 sudah diterima & lolos verifikasi HMAC (baris
      // di atas), yang textbook artinya host SUDAH menyimpan upload kita
      // secara durable SEBELUM membalas (lihat urutan di `_handleRequest`).
      // Kalau proses network gagal SEBELUM sini (timeout/socket/HMAC
      // mismatch), watermark TIDAK maju → sync berikutnya kirim ulang delta
      // yang sama, aman (dedup PK di sisi host).
      await _saveUploadWatermark(db, uploadSyncStartedAt);

      final sent = outDump.values.fold<int>(0, (s, r) => s + r.length);
      final isPending = respPayload['status'] == 'pending_approval';
      return SyncResult(
          received: received, sent: sent, pendingApproval: isPending);
    } finally {
      client.close();
    }
  }
}
