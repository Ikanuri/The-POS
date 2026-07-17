import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/services/cloudflare_publish_service.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Fake channel handler: FlutterSecureStorage asli, tapi backing store-nya
/// Map in-memory (pola sama seperti device_provider_secure_storage_test.dart)
/// — tidak menyentuh Android Keystore sungguhan di test.
Map<String, String> _installFakeSecureStorage() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        return store[call.arguments['key']];
      case 'write':
        store[call.arguments['key']] = call.arguments['value'];
        return null;
      case 'delete':
        store.remove(call.arguments['key']);
        return null;
      case 'readAll':
        return store;
      case 'deleteAll':
        store.clear();
        return null;
      default:
        return null;
    }
  });
  return store;
}

class _FakeCloudflareApi implements CloudflareApi {
  final List<String> ensureProjectCalls = [];
  final List<String> uploadCalls = [];
  bool throwOnEnsure = false;
  bool throwOnUpload = false;

  @override
  Future<void> ensureProject({
    required String accountId,
    required String apiToken,
    required String projectName,
  }) async {
    if (throwOnEnsure) {
      throw CloudflarePublishException('simulasi token invalid');
    }
    ensureProjectCalls.add(projectName);
  }

  @override
  Future<void> uploadDeployment({
    required String accountId,
    required String apiToken,
    required String projectName,
    required String html,
  }) async {
    if (throwOnUpload) {
      throw CloudflarePublishException('simulasi upload gagal');
    }
    uploadCalls.add(html);
  }
}

/// Item 37 — CloudflarePublishService: kredensial di secure storage, nama
/// project DETERMINISTIK (dihitung sekali & tidak berubah walau storeName
/// diganti), dan publish() melempar exception spesifik kalau kredensial
/// belum diisi (supaya UI bisa fallback ke share manual, bukan crash).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test('publish() melempar CloudflareNotConfiguredException kalau '
      'token/account id belum diisi', () async {
    _installFakeSecureStorage();
    final service = CloudflarePublishService(api: _FakeCloudflareApi());

    expect(
      () => service.publish(
          html: '<html></html>', storeName: 'Toko A', storeUuid: 'uuid-1'),
      throwsA(isA<CloudflareNotConfiguredException>()),
    );
  });

  test('setelah saveCredentials, publish() sukses & memanggil ensureProject '
      '+ uploadDeployment dgn project name yang sama', () async {
    _installFakeSecureStorage();
    final api = _FakeCloudflareApi();
    final service = CloudflarePublishService(api: api);
    await service.saveCredentials(apiToken: 'tok123', accountId: 'acc123');

    final result = await service.publish(
        html: '<html>katalog</html>',
        storeName: 'Toko Sembako Jaya',
        storeUuid: 'uuid-abc');

    expect(api.ensureProjectCalls, [result.projectName]);
    expect(api.uploadCalls, ['<html>katalog</html>']);
    expect(result.url, 'https://${result.projectName}.pages.dev');
    expect(result.projectName, startsWith('toko-sembako-jaya-'));
  });

  test('nama project DIHITUNG SEKALI & TIDAK berubah walau storeName '
      'berganti di publish berikutnya (URL tetap valid utk pelanggan)',
      () async {
    _installFakeSecureStorage();
    final api = _FakeCloudflareApi();
    final service = CloudflarePublishService(api: api);
    await service.saveCredentials(apiToken: 'tok', accountId: 'acc');

    final first = await service.publish(
        html: '<a>', storeName: 'Toko Lama', storeUuid: 'uuid-fixed');
    final second = await service.publish(
        html: '<b>', storeName: 'Toko Nama Baru', storeUuid: 'uuid-fixed');

    expect(second.projectName, first.projectName);
  });

  test('dua toko (storeUuid beda) dgn nama toko SAMA menghasilkan project '
      'name BERBEDA (menghindari tabrakan subdomain pages.dev global)',
      () async {
    // Dua device/toko TERPISAH → secure storage terpisah juga (bukan
    // berbagi map yang sama, beda dari test lain di file ini).
    _installFakeSecureStorage();
    final serviceA = CloudflarePublishService(api: _FakeCloudflareApi());
    final nameA = await serviceA.ensureProjectName(
        storeName: 'Toko Barokah', storeUuid: 'uuid-toko-a');

    _installFakeSecureStorage();
    final serviceB = CloudflarePublishService(api: _FakeCloudflareApi());
    final nameB = await serviceB.ensureProjectName(
        storeName: 'Toko Barokah', storeUuid: 'uuid-toko-b');

    expect(nameA, isNot(equals(nameB)));
  });

  test('kredensial persist lewat instance service BARU (baca ulang dari '
      'secure storage — simulasi app reinstall + paste token yang sama)',
      () async {
    _installFakeSecureStorage();
    final first = CloudflarePublishService(api: _FakeCloudflareApi());
    await first.saveCredentials(apiToken: 'tok-asli', accountId: 'acc-asli');

    final second = CloudflarePublishService(api: _FakeCloudflareApi());
    final creds = await second.loadCredentials();

    expect(creds, isNotNull);
    expect(creds!.apiToken, 'tok-asli');
    expect(creds.accountId, 'acc-asli');
  });

  test('clearCredentials() menghapus token & account id', () async {
    _installFakeSecureStorage();
    final service = CloudflarePublishService(api: _FakeCloudflareApi());
    await service.saveCredentials(apiToken: 'x', accountId: 'y');
    await service.clearCredentials();

    expect(await service.loadCredentials(), isNull);
  });

  test('publish() melempar CloudflarePublishException apa adanya kalau API '
      'gagal (mis. token invalid) — bukan ditelan diam-diam', () async {
    _installFakeSecureStorage();
    final api = _FakeCloudflareApi()..throwOnEnsure = true;
    final service = CloudflarePublishService(api: api);
    await service.saveCredentials(apiToken: 'bad-token', accountId: 'acc');

    expect(
      () => service.publish(
          html: '<x>', storeName: 'Toko', storeUuid: 'uuid-x'),
      throwsA(isA<CloudflarePublishException>()),
    );
  });
}
