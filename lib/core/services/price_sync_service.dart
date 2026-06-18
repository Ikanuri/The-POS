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
  });

  final String productName;
  final String? kodeProduk;
  final String? barcode;
  final String unitTypeName;
  final int price;
  final int costPrice;

  Map<String, Object?> toJson() => {
        'productName': productName,
        'kodeProduk': kodeProduk,
        'barcode': barcode,
        'unitTypeName': unitTypeName,
        'price': price,
        'costPrice': costPrice,
      };

  factory PriceCatalogItem.fromJson(Map<String, dynamic> json) =>
      PriceCatalogItem(
        productName: json['productName'] as String,
        kodeProduk: json['kodeProduk'] as String?,
        barcode: json['barcode'] as String?,
        unitTypeName: json['unitTypeName'] as String? ?? '',
        price: json['price'] as int? ?? 0,
        costPrice: json['costPrice'] as int? ?? 0,
      );
}

class PriceSyncService {
  PriceSyncService._();

  static HttpServer? _server;
  static String? _pairingCode;
  static AppDatabase? _db;

  static String _generateCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  // ─── Host ──────────────────────────────────────────────────────────

  static Future<(String, String)> startHost({required AppDatabase db}) async {
    await stopHost();
    _db = db;
    _pairingCode = _generateCode();

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
  }

  static bool get isHostRunning => _server != null;

  static Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.method != 'GET' || request.url.path != 'prices') {
      return shelf.Response.notFound('Not found');
    }

    final code = request.headers['x-pairing-code'] ?? '';
    if (code != _pairingCode) {
      return shelf.Response.forbidden('Invalid code');
    }

    try {
      final catalog = await _buildCatalog(_db!);
      final json = jsonEncode(catalog.map((c) => c.toJson()).toList());
      return shelf.Response.ok(json,
          headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return shelf.Response.internalServerError(body: 'Failed: $e');
    }
  }

  static Future<List<PriceCatalogItem>> _buildCatalog(AppDatabase db) async {
    final rows = await db.customSelect('''
      SELECT p.name AS product_name, p.kode_produk,
             ut.name AS unit_type_name,
             pt.price, pt.cost_price,
             pb.barcode
      FROM products p
      JOIN product_units pu ON pu.product_id = p.id
      JOIN price_tiers pt ON pt.product_unit_id = pu.id AND pt.min_qty = 1
      LEFT JOIN unit_types ut ON ut.id = pu.unit_type_id
      LEFT JOIN (
        SELECT product_unit_id, barcode
        FROM product_barcodes
        WHERE is_primary = 1
        GROUP BY product_unit_id
      ) pb ON pb.product_unit_id = pu.id
      WHERE p.is_active = 1
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
