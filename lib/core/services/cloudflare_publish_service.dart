import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/blake3.dart';

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
  const CloudflarePublishResult({required this.url, required this.projectName});
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
  const HttpCloudflareApi({this.base = 'https://api.cloudflare.com/client/v4'});

  /// Alamat dasar API — diganti server lokal HANYA di test.
  final String base;

  String get _base => base;

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

  /// Direct Upload API Cloudflare Pages (alur yang sama dgn Wrangler):
  /// 1) minta JWT upload, 2) unggah berkas (base64) ke penyimpanan aset,
  /// 3) catat hash-nya, 4) buat deployment berisi `manifest` (path -> hash).
  /// Hash berkas = BLAKE3(base64(isi) + ekstensi) dipotong 32 heks — bukan
  /// SHA biasa; hash yang salah membuat halaman 404 diam-diam.
  @override
  Future<void> uploadDeployment({
    required String accountId,
    required String apiToken,
    required String projectName,
    required String html,
  }) async {
    final b64 = base64.encode(utf8.encode(html));
    final hash = cloudflareFileHash(b64, 'html');

    // 1) JWT upload (GET; sebagian akun/versi API menerima POST).
    final tokenUrl =
        '$_base/accounts/$accountId/pages/projects/$projectName/upload-token';
    var tokenRes = await _json('GET', tokenUrl, apiToken);
    if (tokenRes.status == 404 || tokenRes.status == 405) {
      tokenRes = await _json('POST', tokenUrl, apiToken);
    }
    final jwt = _decode(tokenRes.body)?['result']?['jwt'] as String?;
    if (tokenRes.status != 200 || jwt == null) {
      throw CloudflarePublishException(
          'Gagal meminta izin upload Cloudflare Pages (${tokenRes.status}): '
          '${tokenRes.body}');
    }

    // 2) unggah berkas.
    final up = await _json(
        'POST',
        '$_base/pages/assets/upload',
        jwt,
        jsonEncode([
          {
            'key': hash,
            'value': b64,
            'metadata': {'contentType': 'text/html'},
            'base64': true,
          }
        ]));
    if (up.status != 200) {
      throw CloudflarePublishException(
          'Gagal upload ke Cloudflare Pages (${up.status}): ${up.body}');
    }

    // 3) catat hash.
    final upsert = await _json(
        'POST',
        '$_base/pages/assets/upsert-hashes',
        jwt,
        jsonEncode({
          'hashes': [hash]
        }));
    if (upsert.status != 200) {
      throw CloudflarePublishException(
          'Gagal mencatat berkas Cloudflare Pages (${upsert.status}): '
          '${upsert.body}');
    }

    // 4) deployment: hanya `manifest` (+ branch) — berkas sudah di langkah 2.
    final client = HttpClient();
    try {
      final boundary =
          '----BerkahPOSBoundary${DateTime.now().microsecondsSinceEpoch}';
      final buffer = BytesBuilder();
      void field(String name, String value) {
        buffer.add(ascii.encode('--$boundary\r\n'));
        buffer.add(ascii
            .encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
        buffer.add(utf8.encode(value));
        buffer.add(ascii.encode('\r\n'));
      }

      field('manifest', jsonEncode({'/index.html': hash}));
      field('branch', 'main');
      buffer.add(ascii.encode('--$boundary--\r\n'));

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
            'Gagal membuat deployment Cloudflare Pages (${res.statusCode}): '
            '$body');
      }
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  Future<({int status, String body})> _json(
      String method, String url, String bearer,
      [String? body]) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      req.headers.set('Authorization', 'Bearer $bearer');
      if (body != null) {
        req.headers.set('Content-Type', 'application/json');
        req.write(body);
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return (status: res.statusCode, body: text);
    } finally {
      client.close(force: true);
    }
  }
}

/// Hash berkas ala Cloudflare Pages: BLAKE3(base64 + ekstensi tanpa titik),
/// 32 karakter heks pertama. Diekspos agar bisa diuji.
String cloudflareFileHash(String base64Content, String extension) =>
    blake3Hex(utf8.encode('$base64Content$extension')).substring(0, 32);

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
