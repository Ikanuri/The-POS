import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/services/temp_share_cleanup.dart';

/// Fake path_provider — arahkan getTemporaryDirectory ke folder temp asli
/// tanpa platform channel (pola sama dengan `crash_log_service_test.dart`).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

/// Item 8 — file share sementara (struk/katalog) sebelumnya tidak pernah
/// dihapus, menumpuk selamanya di temp dir.
void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_temp_share_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, {required DateTime modified}) {
    final f = File('${tempDir.path}/$name')..writeAsStringSync('x');
    f.setLastModifiedSync(modified);
    return f;
  }

  test('menghapus struk_*/katalog_* yang lebih tua dari 24 jam', () async {
    final old = writeFile('struk_K1-1.png',
        modified: DateTime.now().subtract(const Duration(days: 2)));
    final oldKatalog = writeFile('katalog_pesanan_20260101.html',
        modified: DateTime.now().subtract(const Duration(days: 3)));

    await TempShareCleanup.run();

    expect(old.existsSync(), isFalse);
    expect(oldKatalog.existsSync(), isFalse);
  });

  test('TIDAK menghapus struk_*/katalog_* yang masih baru (<24 jam)',
      () async {
    final fresh = writeFile('struk_K1-2.png',
        modified: DateTime.now().subtract(const Duration(hours: 1)));

    await TempShareCleanup.run();

    expect(fresh.existsSync(), isTrue,
        reason: 'file baru mungkin masih dibaca share sheet/app tujuan');
  });

  test('TIDAK menyentuh file lain yang bukan struk_*/katalog_* (mis. file '
      'sistem/aplikasi lain di temp dir)', () async {
    final unrelated = writeFile('some_other_cache_file.tmp',
        modified: DateTime.now().subtract(const Duration(days: 5)));

    await TempShareCleanup.run();

    expect(unrelated.existsSync(), isTrue);
  });
}
