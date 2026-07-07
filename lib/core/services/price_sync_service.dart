import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../database/app_database.dart';

const _kPriceSyncPort = 8626;
const _kMaxPayloadBytes = 10 * 1024 * 1024;

class PriceCatalogItem {
  const PriceCatalogItem({
    required this.productName,
    this.kodeProduk,
    this.barcode,
    required this.unitTypeName,
    required this.price,
    required this.costPrice,
    this.parentName,
    this.parentKode,
    this.isBaseUnit = true,
    this.ratioToBase = 1.0,
  });

  final String productName;
  final String? kodeProduk;
  final String? barcode;
  final String unitTypeName;
  final int price;
  final int costPrice;

  /// Identitas induk bila item ini varian (parentProductId pada host).
  /// Dipakai klien untuk merekonstruksi relasi varian saat menambah produk.
  final String? parentName;
  final String? parentKode;

  /// Atribut satuan agar klien bisa mencocokkan ke unit yang tepat (bukan
  /// asal unit pertama) dan membuat unit baru dengan rasio yang benar.
  final bool isBaseUnit;
  final double ratioToBase;

  bool get isVariant =>
      (parentName != null && parentName!.trim().isNotEmpty) ||
      (parentKode != null && parentKode!.trim().isNotEmpty);

  Map<String, Object?> toJson() => {
        'productName': productName,
        'kodeProduk': kodeProduk,
        'barcode': barcode,
        'unitTypeName': unitTypeName,
        'price': price,
        'costPrice': costPrice,
        'parentName': parentName,
        'parentKode': parentKode,
        'isBaseUnit': isBaseUnit,
        'ratioToBase': ratioToBase,
      };

  factory PriceCatalogItem.fromJson(Map<String, dynamic> json) =>
      PriceCatalogItem(
        productName: json['productName'] as String,
        kodeProduk: json['kodeProduk'] as String?,
        barcode: json['barcode'] as String?,
        unitTypeName: json['unitTypeName'] as String? ?? '',
        price: json['price'] as int? ?? 0,
        costPrice: json['costPrice'] as int? ?? 0,
        parentName: json['parentName'] as String?,
        parentKode: json['parentKode'] as String?,
        isBaseUnit: json['isBaseUnit'] as bool? ?? true,
        ratioToBase: (json['ratioToBase'] as num?)?.toDouble() ?? 1.0,
      );
}

class PriceSyncService {
  PriceSyncService._();

  static HttpServer? _server;
  static String? _pairingCode;
  static AppDatabase? _db;

  // Proteksi brute-force per-IP: kode pairing hanya 6 digit dan katalog yang
  // dilayani memuat HARGA MODAL — tanpa lockout, 1 juta kombinasi bisa
  // dicoba habis dalam hitungan menit oleh siapa pun di WiFi yang sama.
  // Pola sama dengan LanSyncService: 5 kali gagal → tunggu 5 menit.
  static final _failedAttempts = <String, int>{};
  static final _lockoutUntil = <String, DateTime>{};
  static const _kMaxFailures = 5;
  static const _kLockoutDuration = Duration(minutes: 5);

  /// Perbandingan string waktu-konstan — cegah timing side-channel pada kode.
  static bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static String _generateCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  // ─── Host ──────────────────────────────────────────────────────────

  static Future<(String, String)> startHost({required AppDatabase db}) async {
    await stopHost();
    _db = db;
    _pairingCode = _generateCode();
    _failedAttempts.clear();
    _lockoutUntil.clear();

    final handler =
        const shelf.Pipeline().addHandler(_handleRequest);

    _server =
        await shelf_io.serve(handler, InternetAddress.anyIPv4, _kPriceSyncPort);

    final networkInfo = NetworkInfo();
    final ip = await networkInfo.getWifiIP() ?? 'Unknown IP';
    return (ip, _pairingCode!);
  }

  static Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
    _pairingCode = null;
    _failedAttempts.clear();
    _lockoutUntil.clear();
  }

  static bool get isHostRunning => _server != null;

  static Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.method != 'GET' || request.url.path != 'prices') {
      return shelf.Response.notFound('Not found');
    }

    final ip = (request.context['shelf.io.connection_info']
                as HttpConnectionInfo?)
            ?.remoteAddress
            .address ??
        'unknown';
    final lockedUntil = _lockoutUntil[ip];
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      return shelf.Response(429, body: 'Too many attempts. Try again later.');
    }

    final code = request.headers['x-pairing-code'] ?? '';
    if (!_constantTimeEqual(code, _pairingCode ?? '')) {
      _failedAttempts[ip] = (_failedAttempts[ip] ?? 0) + 1;
      if ((_failedAttempts[ip] ?? 0) >= _kMaxFailures) {
        _lockoutUntil[ip] = DateTime.now().add(_kLockoutDuration);
        _failedAttempts.remove(ip);
      }
      return shelf.Response.forbidden('Invalid code');
    }
    _failedAttempts.remove(ip);

    try {
      final catalog = await _buildCatalog(_db!);
      final json = jsonEncode(catalog.map((c) => c.toJson()).toList());
      return shelf.Response.ok(json,
          headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return shelf.Response.internalServerError(body: 'Failed: $e');
    }
  }

  static Future<List<PriceCatalogItem>> buildCatalog(AppDatabase db) =>
      _buildCatalog(db);

  static Future<List<PriceCatalogItem>> _buildCatalog(AppDatabase db) async {
    final rows = await db.customSelect('''
      SELECT p.name AS product_name, p.kode_produk,
             parent.name AS parent_name, parent.kode_produk AS parent_kode,
             ut.name AS unit_type_name,
             pu.is_base_unit AS is_base_unit, pu.ratio_to_base AS ratio_to_base,
             pt.price, pt.cost_price,
             pb.barcode
      FROM products p
      JOIN product_units pu ON pu.product_id = p.id
      JOIN price_tiers pt ON pt.product_unit_id = pu.id AND pt.min_qty = 1
      LEFT JOIN products parent ON parent.id = p.parent_product_id
      LEFT JOIN unit_types ut ON ut.id = pu.unit_type_id
      LEFT JOIN (
        SELECT product_unit_id, barcode
        FROM product_barcodes
        WHERE is_primary = 1
        GROUP BY product_unit_id
      ) pb ON pb.product_unit_id = pu.id
      WHERE p.is_active = 1 AND pt.price > 0
      ORDER BY p.name
    ''').get();

    return rows
        .map((r) => PriceCatalogItem(
              productName: r.data['product_name'] as String,
              kodeProduk: r.data['kode_produk'] as String?,
              barcode: r.data['barcode'] as String?,
              unitTypeName: r.data['unit_type_name'] as String? ?? '',
              price: r.data['price'] as int? ?? 0,
              costPrice: r.data['cost_price'] as int? ?? 0,
              parentName: r.data['parent_name'] as String?,
              parentKode: r.data['parent_kode'] as String?,
              isBaseUnit: ((r.data['is_base_unit'] as int?) ?? 1) == 1,
              ratioToBase:
                  (r.data['ratio_to_base'] as num?)?.toDouble() ?? 1.0,
            ))
        .toList();
  }

  // ─── Client ────────────────────────────────────────────────────────

  static Future<List<PriceCatalogItem>> fetchFromHost({
    required String hostIp,
    required String pairingCode,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.get(hostIp, _kPriceSyncPort, 'prices');
      request.headers.set('x-pairing-code', pairingCode);
      final response = await request.close();

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw Exception('Error ${response.statusCode}: $body');
      }

      final bodyBytes = await response.expand((c) => c).toList();
      if (bodyBytes.length > _kMaxPayloadBytes) {
        throw Exception('Payload terlalu besar');
      }

      final json = utf8.decode(bodyBytes);
      final list = jsonDecode(json) as List;
      return list
          .map((e) => PriceCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      client.close();
    }
  }
}
