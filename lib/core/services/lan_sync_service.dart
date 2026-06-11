import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../database/app_database.dart';
import 'crypto_service.dart';

const _kSyncPort = 8625;

/// Hasil sync satu arah (diterima dari remote).
class SyncResult {
  const SyncResult({required this.received, required this.sent});
  final int received;
  final int sent;
}

class LanSyncService {
  LanSyncService._();

  static HttpServer? _server;
  static String? _syncToken;
  static String? _storeKey;
  static AppDatabase? _db;

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

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _kSyncPort);

    final networkInfo = NetworkInfo();
    final ip = await networkInfo.getWifiIP() ?? 'Unknown IP';
    return (ip, _syncToken!);
  }

  static Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    _syncToken = null;
  }

  static bool get isHostRunning => _server != null;

  static Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.method != 'POST' || request.url.path != 'sync') {
      return shelf.Response.notFound('Not found');
    }
    try {
      final bodyBytes = await request.read().expand((c) => c).toList();
      final token = request.headers['x-sync-token'] ?? '';
      if (token != _syncToken) {
        return shelf.Response.forbidden('Invalid token');
      }

      final key = CryptoService.deriveSyncKey(_storeKey!, _syncToken!);
      final payloadJson = CryptoService.decryptText(
          base64Encode(bodyBytes), Uint8List.fromList(key));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

      final sinceStr = payload['since'] as String?;
      final since = sinceStr != null
          ? DateTime.parse(sinceStr)
          : DateTime.fromMillisecondsSinceEpoch(0);

      // Merge incoming rows.
      const appendOnly = {'transactions', 'transaction_items', 'transaction_payments',
          'stock_ledger', 'loyalty_point_ledger', 'expenses'};
      final tables = payload['tables'] as Map<String, dynamic>? ?? {};
      for (final entry in tables.entries) {
        final rows = (entry.value as List).cast<Map<String, dynamic>>().map((r) {
          return r.map<String, Object?>((k, v) => MapEntry(k, v));
        }).toList();
        await _db!.mergeRows(entry.key, rows, appendOnly.contains(entry.key));
      }

      // Send back rows since.
      final outDump = await _db!.dumpSince(since);
      final outPayload = {'tables': outDump, 'since': DateTime.now().toIso8601String()};
      final outJson = jsonEncode(outPayload);
      final encrypted = CryptoService.encryptText(outJson, Uint8List.fromList(key));

      return shelf.Response.ok(
        base64Decode(encrypted),
        headers: {'content-type': 'application/octet-stream'},
      );
    } catch (e) {
      return shelf.Response.internalServerError(body: 'Error: $e');
    }
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

    final outDump = await db.dumpSince(effectiveSince);
    final payload = {
      'since': effectiveSince.toIso8601String(),
      'tables': outDump,
    };
    final payloadJson = jsonEncode(payload);
    final encrypted = CryptoService.encryptText(payloadJson, Uint8List.fromList(key));
    final encryptedBytes = base64Decode(encrypted);

    final client = HttpClient();
    try {
      final request = await client.post(hostIp, _kSyncPort, 'sync');
      request.headers.set('x-sync-token', syncToken);
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
      for (final entry in tables.entries) {
        final rows = (entry.value as List).cast<Map<String, dynamic>>().map((r) {
          return r.map<String, Object?>((k, v) => MapEntry(k, v));
        }).toList();
        const appendOnly = {'transactions', 'transaction_items', 'transaction_payments',
            'stock_ledger', 'loyalty_point_ledger', 'expenses'};
        received += await db.mergeRows(entry.key, rows, appendOnly.contains(entry.key));
      }

      final sent = outDump.values.fold<int>(0, (s, r) => s + r.length);
      return SyncResult(received: received, sent: sent);
    } finally {
      client.close();
    }
  }
}
