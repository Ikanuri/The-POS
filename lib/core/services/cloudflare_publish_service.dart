import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Item 37 — publish katalog HTML otomatis ke Cloudflare Pages (Direct
/// Upload API, HTTP murni tanpa Git/CLI/Wrangler). Nama project Cloudflare
/// Pages DETERMINISTIK: slug(storeName) + suffix hex storeUuid, dihitung
/// SEKALI saat publish pertama & disimpan (bukan diketik user, bukan
/// dihitung ulang tiap publish) — supaya URL yang sudah dibagikan ke
/// pelanggan tetap valid walau [storeName] diganti belakangan. Suffix uuid
/// WAJIB ada (bukan cuma slug nama toko) karena subdomain `<project>.pages.
/// dev` unik SECARA GLOBAL lintas akun Cloudflare siapa pun, bukan cuma per
/// akun — lihat rasional lengkap di PLAN.md Item 37.
class CloudflareNotConfiguredException implements Exception {
  const CloudflareNotConfiguredException();
  @override
  String toString() =>
      'Token/Account ID Cloudflare belum diisi — buka Pengaturan > Publish ke Web';
}

class CloudflarePublishException implements Exception {
  CloudflarePublishException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CloudflareCredentials {
  const CloudflareCredentials(
      {required this.apiToken, required this.accountId});
  final String apiToken;
  final String accountId;
}

class CloudflarePublishResult {
  const CloudflarePublishResult(
      {required this.url, required this.projectName});
  final String url;
  final String projectName;
}

/// Abstraksi pemanggilan Cloudflare API — memungkinkan diganti fake di unit
/// test (tidak mungkin hit API sungguhan tanpa akun/token Cloudflare nyata).
abstract class CloudflareApi {
  Future<void> ensureProject({
    required String accountId,
    required String apiToken,
    required String projectName,
  });

  Future<void> uploadDeployment({
    required String accountId,
    required String apiToken,
    required String projectName,
    required String html,
  });
}

/// Implementasi nyata via `dart:io HttpClient` (pola sama seperti
/// `lan_sync_service.dart` — project ini sudah pakai HttpClient mentah,
/// bukan package `http`, jadi konsisten tanpa dependency baru).
class HttpCloudflareApi implements CloudflareApi {
  const HttpCloudflareApi();

  static const _base = 'https://api.cloudflare.com/client/v4';

  @override
  Future<void> ensureProject({
    required String accountId,
    required String apiToken,
    required String projectName,
  }) async {
    final client = HttpClient();
    try {
      final req = await client
          .postUrl(Uri.parse('$_base/accounts/$accountId/pages/projects'));
      req.headers.set('Authorization', 'Bearer $apiToken');
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({
        'name': projectName,
        'production_branch': 'main',
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      // Kode/pesan "project sudah ada" BUKAN kegagalan — itu kasus normal
      // saat republish ke project yang sama (nama deterministik, lihat
      // dokumentasi kelas). Error lain (token invalid, dll) baru dilempar.
      final alreadyExists = res.statusCode == 409 ||
          body.contains('already exists') ||
          body.contains('"code":10014');
      if (res.statusCode != 200 && !alreadyExists) {
        throw CloudflarePublishException(
            'Gagal membuat project Cloudflare Pages (${res.statusCode}): $body');
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> uploadDeployment({
    required String accountId,
    required String apiToken,
    required String projectName,
    required String html,
  }) async {
    final client = HttpClient();
    try {
      final boundary =
          '----BerkahPOSBoundary${DateTime.now().microsecondsSinceEpoch}';
      final buffer = BytesBuilder();
      buffer.add(ascii.encode('--$boundary\r\n'));
      buffer.add(ascii.encode(
          'Content-Disposition: form-data; name="index.html"; filename="index.html"\r\n'));
      buffer.add(ascii.encode('Content-Type: text/html\r\n\r\n'));
      buffer.add(utf8.encode(html));
      buffer.add(ascii.encode('\r\n--$boundary--\r\n'));

      final req = await client.postUrl(Uri.parse(
          '$_base/accounts/$accountId/pages/projects/$projectName/deployments'));
      req.headers.set('Authorization', 'Bearer $apiToken');
      req.headers
          .set('Content-Type', 'multipart/form-data; boundary=$boundary');
      req.add(buffer.toBytes());
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw CloudflarePublishException(
            'Gagal upload ke Cloudflare Pages (${res.statusCode}): $body');
      }
    } finally {
      client.close(force: true);
    }
  }
}

class CloudflarePublishService {
  CloudflarePublishService({CloudflareApi? api, FlutterSecureStorage? storage})
      : _api = api ?? const HttpCloudflareApi(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final CloudflareApi _api;
  final FlutterSecureStorage _storage;

  static const _kApiToken = 'cf_api_token';
  static const _kAccountId = 'cf_account_id';
  static const _kProjectName = 'cf_project_name';

  Future<CloudflareCredentials?> loadCredentials() async {
    final token = await _storage.read(key: _kApiToken);
    final accountId = await _storage.read(key: _kAccountId);
    if (token == null ||
        token.isEmpty ||
        accountId == null ||
        accountId.isEmpty) {
      return null;
    }
    return CloudflareCredentials(apiToken: token, accountId: accountId);
  }

  Future<void> saveCredentials(
      {required String apiToken, required String accountId}) async {
    await _storage.write(key: _kApiToken, value: apiToken);
    await _storage.write(key: _kAccountId, value: accountId);
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _kApiToken);
    await _storage.delete(key: _kAccountId);
  }

  /// Nama project Cloudflare Pages — dihitung SEKALI (lihat dokumentasi
  /// kelas) & disimpan; publish berikutnya SELALU pakai nama yang sama
  /// persis meski [storeName] berubah, supaya URL tetap valid.
  Future<String> ensureProjectName(
      {required String storeName, required String storeUuid}) async {
    final cached = await _storage.read(key: _kProjectName);
    if (cached != null && cached.isNotEmpty) return cached;
    final name = '${_slugify(storeName)}-${_shortHash(storeUuid)}';
    await _storage.write(key: _kProjectName, value: name);
    return name;
  }

  static String _slugify(String input) {
    var s = input.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^-|-$'), '');
    if (s.isEmpty) s = 'toko';
    // Batas panjang nama project Cloudflare Pages (58 char) — sisakan
    // ruang utk separator + suffix hex 6 karakter.
    if (s.length > 40) s = s.substring(0, 40);
    return s;
  }

  /// BUKAN hash kriptografis — cukup deterministik & pendek utk mengurangi
  /// risiko tabrakan nama project lintas akun Cloudflare (lihat dokumentasi
  /// kelas). storeUuid sudah unik per toko, hash ini murni representasi
  /// pendeknya di URL.
  static String _shortHash(String input) {
    var hash = 0;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0xFFFFFFFF;
    }
    // Ambil 6 digit hex TERAKHIR (bukan pertama) — dua input yang cuma
    // beda di akhir string (mis. "uuid-toko-a" vs "uuid-toko-b") hanya
    // mengubah bit-bit RENDAH hash ini; substring dari depan akan
    // membuang justru digit yang membedakan keduanya.
    final hex = hash.toRadixString(16).padLeft(8, '0');
    return hex.substring(hex.length - 6);
  }

  /// Publish [html] ke Cloudflare Pages. Melempar
  /// [CloudflareNotConfiguredException] kalau token/account id belum
  /// diisi — pemanggil (UI) harus tangkap ini & arahkan ke fallback share
  /// manual (offline-first: fitur ekspor katalog TIDAK boleh bergantung ke
  /// internet).
  Future<CloudflarePublishResult> publish({
    required String html,
    required String storeName,
    required String storeUuid,
  }) async {
    final creds = await loadCredentials();
    if (creds == null) throw const CloudflareNotConfiguredException();
    final projectName =
        await ensureProjectName(storeName: storeName, storeUuid: storeUuid);
    await _api.ensureProject(
        accountId: creds.accountId,
        apiToken: creds.apiToken,
        projectName: projectName);
    await _api.uploadDeployment(
        accountId: creds.accountId,
        apiToken: creds.apiToken,
        projectName: projectName,
        html: html);
    return CloudflarePublishResult(
        url: 'https://$projectName.pages.dev', projectName: projectName);
  }
}
