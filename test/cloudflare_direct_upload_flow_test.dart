import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/services/cloudflare_publish_service.dart';

/// Alur Direct Upload 4 tahap (upload-token -> assets/upload -> upsert-hashes
/// -> deployments dgn `manifest`) dijalankan terhadap server lokal tiruan
/// yang memvalidasi bentuk permintaan seperti Cloudflare. Regresi: versi
/// lama hanya mengirim berkas -> 400 "A manifest field was expected".
Future<T> _withRealHttp<T>(Future<T> Function() body) => HttpOverrides.runZoned(
      body,
      createHttpClient: (context) => Zone.root.run(() {
        final prevGlobal = HttpOverrides.current;
        HttpOverrides.global = null;
        try {
          return HttpClient(context: context);
        } finally {
          HttpOverrides.global = prevGlobal;
        }
      }),
    );

void main() {
  test('cloudflareFileHash = blake3(base64+ekstensi)[0:32] (nilai referensi)',
      () {
    final b64 = base64.encode(utf8.encode('<html>hi</html>'));
    expect(cloudflareFileHash(b64, 'html'), 'c7c80743d6c079822f72f66347942cee');
  });

  test('uploadDeployment menjalankan 4 tahap dgn manifest yang benar',
      () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final log = <String>[];
    String? uploadedKey;
    String? manifest;
    server.listen((req) async {
      final path = req.uri.path;
      final bodyBytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      final body = utf8.decode(bodyBytes);
      log.add('${req.method} $path');
      Future<void> ok(Object? result) async {
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'success': true, 'result': result}));
        await req.response.close();
      }

      if (path.endsWith('/upload-token')) {
        expect(req.headers.value('authorization'), 'Bearer API');
        return ok({'jwt': 'JWT123'});
      }
      if (path.endsWith('/pages/assets/upload')) {
        expect(req.headers.value('authorization'), 'Bearer JWT123');
        final list = jsonDecode(body) as List;
        uploadedKey = list.first['key'] as String;
        expect(list.first['base64'], true);
        return ok({'successful_key_count': 1});
      }
      if (path.endsWith('/upsert-hashes')) {
        expect(req.headers.value('authorization'), 'Bearer JWT123');
        expect((jsonDecode(body)['hashes'] as List).single, uploadedKey);
        return ok(null);
      }
      if (path.endsWith('/deployments')) {
        expect(req.headers.value('authorization'), 'Bearer API');
        final m = RegExp(r'name="manifest"\r\n\r\n(.*?)\r\n').firstMatch(body);
        manifest = m?.group(1);
        return ok({'id': 'd1'});
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    await _withRealHttp(() =>
        HttpCloudflareApi(base: 'http://127.0.0.1:${server.port}/client/v4')
            .uploadDeployment(
                accountId: 'ACC',
                apiToken: 'API',
                projectName: 'toko-abc',
                html: '<html>katalog</html>'));

    expect(log, [
      'GET /client/v4/accounts/ACC/pages/projects/toko-abc/upload-token',
      'POST /client/v4/pages/assets/upload',
      'POST /client/v4/pages/assets/upsert-hashes',
      'POST /client/v4/accounts/ACC/pages/projects/toko-abc/deployments',
    ]);
    expect(manifest, isNotNull, reason: 'deployment WAJIB membawa manifest');
    expect(jsonDecode(manifest!), {'/index.html': uploadedKey});
    expect(uploadedKey, hasLength(32));
  });
}
