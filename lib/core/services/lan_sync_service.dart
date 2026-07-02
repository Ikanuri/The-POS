import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../database/app_database.dart';
import 'crypto_service.dart';

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

class LanSyncService {
  LanSyncService._();

  static HttpServer? _server;
  static String? _syncToken;
  static String? _storeKey;
  static AppDatabase? _db;

  // Simple per-IP brute-force protection: 5 failures → 5-min lockout.
  static final _failedAttempts = <String, int>{};
  static final _lockoutUntil = <String, DateTime>{};
  static const _kMaxFailures = 5;
  static const _kLockoutDuration = Duration(minutes: 5);

  // B-4: Antrian sync menunggu persetujuan owner.
  static final _pendingQueue = <PendingSyncItem>[];
  // Callback dipanggil saat antrian berubah (UI bisa listen).
  static void Function()? onQueueChanged;

  static List<PendingSyncItem> get pendingQueue =>
      List.unmodifiable(_pendingQueue);

  /// Tabel append-only yang boleh diunggah klien ke host. Master data tidak
  /// pernah di-merge dari klien (alir satu arah host → bawahan).
  static const appendOnlyTables = {
    'transactions', 'transaction_items', 'transaction_payments',
    'stock_ledger', 'loyalty_point_ledger', 'expenses',
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

    final handler = const shelf.Pipeline()
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _kSyncPort);

    final networkInfo = NetworkInfo();
    final ip = await networkInfo.getWifiIP() ?? 'Unknown IP';
    return (ip, _syncToken!);
  }

  /// Setujui item antrian → merge data ke DB, kirim balik data host.
  ///
  /// [allowedTables] (opsional) membatasi tabel mana yang di-merge — dipakai
  /// owner untuk memilih kategori data yang diterima. Bila null, semua tabel
  /// append-only diterima. Master data dari klien tidak pernah di-merge.
  static Future<int> approveSync(String itemId,
      {Set<String>? allowedTables}) async {
    final idx = _pendingQueue.indexWhere((i) => i.id == itemId);
    if (idx < 0) return 0;
    final item = _pendingQueue.removeAt(idx);
    onQueueChanged?.call();

    int received = 0;
    final touchedTxIds = <String>{};
    for (final entry in item.tables.entries) {
      // Guard satu arah: hanya tabel append-only yang boleh dari klien.
      if (!appendOnlyTables.contains(entry.key)) continue;
      // Filter kategori yang dipilih owner.
      if (allowedTables != null && !allowedTables.contains(entry.key)) continue;
      received += await _db!.mergeRows(entry.key, entry.value, true);
      _collectTxIds(entry.key, entry.value, touchedTxIds);
    }
    // Rekonsiliasi total/paid dari child rows sebelum membangun ringkasan.
    // Id diambil juga dari item/pembayaran, sehingga transaksi lama yang hanya
    // menerima cicilan / item susulan via sync ikut dikoreksi headernya.
    await _db!.reconcileTransactionsByIds(touchedTxIds);
    await _db!.rebuildSummariesForTxIds(touchedTxIds);
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

  /// Tolak item antrian tanpa merge.
  static void rejectSync(String itemId) {
    _pendingQueue.removeWhere((i) => i.id == itemId);
    onQueueChanged?.call();
  }

  static Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    _syncToken = null;
    _failedAttempts.clear();
    _lockoutUntil.clear();
    _usedNonces.clear();
  }

  static bool get isHostRunning => _server != null;

  static Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.method != 'POST' || request.url.path != 'sync') {
      return shelf.Response.notFound('Not found');
    }

    final ip = (request.context['shelf.io.connection_info']
            as HttpConnectionInfo?)
        ?.remoteAddress
        .address ?? 'unknown';

    // Rate-limiting: check lockout before reading body.
    final lockedUntil = _lockoutUntil[ip];
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      return shelf.Response(429, body: 'Too many attempts. Try again later.');
    }

    // Reject oversized payloads before buffering (DoS protection).
    final declaredLength =
        int.tryParse(request.headers['content-length'] ?? '') ?? 0;
    if (declaredLength > _kMaxPayloadBytes) {
      return shelf.Response(413, body: 'Payload too large');
    }

    try {
      final bodyBytes = await request.read().expand((c) => c).toList();
      if (bodyBytes.length > _kMaxPayloadBytes) {
        return shelf.Response(413, body: 'Payload too large');
      }

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
      // Tolak timestamp lebih dari 5 menit dari sekarang.
      final ts = DateTime.tryParse(tsStr);
      if (ts == null ||
          DateTime.now().difference(ts).abs() > const Duration(minutes: 5)) {
        return shelf.Response(400, body: 'Timestamp out of window');
      }
      // Tolak nonce yang sudah pernah dipakai (replay prevention).
      if (_usedNonces.contains(nonce)) {
        return shelf.Response(400, body: 'Nonce replayed');
      }
      final hmacKey = CryptoService.deriveSyncHmacKey(_storeKey!, _syncToken!);
      final expectedHmac = CryptoService.hmacSha256(
        utf8.encode('$nonce:$tsStr:${base64Encode(bodyBytes)}'),
        hmacKey,
      );
      final expectedHex =
          expectedHmac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (!_constantTimeEqual(clientHmac, expectedHex)) {
        return shelf.Response.forbidden('HMAC mismatch');
      }
      _usedNonces.add(nonce);

      final key = CryptoService.deriveSyncKey(_storeKey!, _syncToken!);
      final payloadJson = CryptoService.decryptText(
          base64Encode(bodyBytes), Uint8List.fromList(key));
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

      final itemId = _generateNonce();
      _pendingQueue.add(PendingSyncItem(
        id: itemId,
        fromIp: ip,
        arrivedAt: DateTime.now(),
        tables: tables,
        since: since,
        tablesSummary: summary,
      ));
      onQueueChanged?.call();

      // Immediately send back the host's data since the client's timestamp.
      // The client receives host updates even before their data is approved.
      final outDump = await _db!.dumpSince(since);
      final outPayload = {
        'tables': outDump,
        'since': DateTime.now().toIso8601String(),
        'pendingId': itemId,
        'status': 'pending_approval',
      };
      final outJson = jsonEncode(outPayload);
      final encrypted = CryptoService.encryptText(outJson, Uint8List.fromList(key));

      return shelf.Response.ok(
        base64Decode(encrypted),
        headers: {'content-type': 'application/octet-stream'},
      );
    } catch (e) {
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
    'product_barcodes': 'barcode',
    'customers': 'pelanggan',
    'customer_groups': 'grup pelanggan',
    'customer_group_prices': 'harga grup',
    'kasir_permissions': 'izin kasir',
  };

  static String _tableLabel(String tableName) =>
      _kTableLabels[tableName] ?? tableName;

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

  static Future<SyncResult> syncToHost({
    required AppDatabase db,
    required String storeKey,
    required String hostIp,
    required String syncToken,
    DateTime? since,
  }) async {
    final key = CryptoService.deriveSyncKey(storeKey, syncToken);
    final effectiveSince = since ?? DateTime.fromMillisecondsSinceEpoch(0);

    // Klien (perangkat bawahan) hanya mengirim data append-only ke atas.
    // Master data (produk, harga, izin) tidak diunggah agar tidak menimpa
    // data owner — master data mengalir satu arah dari host ke bawah.
    final outDump =
        await db.dumpSince(effectiveSince, includeMasterData: false);
    final payload = {
      'since': effectiveSince.toIso8601String(),
      'tables': outDump,
    };
    final payloadJson = jsonEncode(payload);
    final encrypted = CryptoService.encryptText(payloadJson, Uint8List.fromList(key));
    final encryptedBytes = base64Decode(encrypted);

    // B-3: Tambah nonce + timestamp + HMAC ke setiap request.
    final nonce = _generateNonce();
    final tsStr = DateTime.now().toUtc().toIso8601String();
    final hmacKey = CryptoService.deriveSyncHmacKey(storeKey, syncToken);
    final hmac = CryptoService.hmacSha256(
      utf8.encode('$nonce:$tsStr:${base64Encode(encryptedBytes)}'),
      hmacKey,
    );
    final hmacHex =
        hmac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final client = HttpClient();
    try {
      final request = await client.post(hostIp, _kSyncPort, 'sync');
      request.headers.set('x-sync-token', syncToken);
      request.headers.set('x-sync-nonce', nonce);
      request.headers.set('x-sync-ts', tsStr);
      request.headers.set('x-sync-hmac', hmacHex);
      request.headers.set('content-type', 'application/octet-stream');
      request.add(encryptedBytes);
      final response = await request.close();

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw Exception('Server error ${response.statusCode}: $body');
      }

      final respBytes = await response.expand((c) => c).toList();
      final respJson = CryptoService.decryptText(
          base64Encode(respBytes), Uint8List.fromList(key));
      final respPayload = jsonDecode(respJson) as Map<String, dynamic>;

      int received = 0;
      final tables = respPayload['tables'] as Map<String, dynamic>? ?? {};
      final touchedTxIds = <String>{};
      for (final entry in tables.entries) {
        final rows = (entry.value as List).cast<Map<String, dynamic>>().map((r) {
          return r.map<String, Object?>((k, v) => MapEntry(k, v));
        }).toList();
        // Klien menerima data dari host: master data di-merge last-write-wins
        // (data owner menang), append-only di-INSERT OR IGNORE.
        received += await db.mergeRows(
            entry.key, rows, appendOnlyTables.contains(entry.key));
        _collectTxIds(entry.key, rows, touchedTxIds);
      }
      // Rekonsiliasi total/paid dari child rows, lalu refresh ringkasan harian
      // untuk tanggal yang tersentuh — termasuk transaksi lama yang hanya
      // menerima cicilan / item susulan (headernya tidak ada di payload).
      await db.reconcileTransactionsByIds(touchedTxIds);
      await db.rebuildSummariesForTxIds(touchedTxIds);

      final sent = outDump.values.fold<int>(0, (s, r) => s + r.length);
      final isPending =
          respPayload['status'] == 'pending_approval';
      return SyncResult(received: received, sent: sent, pendingApproval: isPending);
    } finally {
      client.close();
    }
  }
}
