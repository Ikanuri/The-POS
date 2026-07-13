import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/services/crash_log_service.dart';

/// Fake path_provider — arahkan getExternalStorageDirectory ke folder temp
/// asli tanpa platform channel (pola sama dengan `db_fixes_test.dart`).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.externalPath);
  final String? externalPath;

  @override
  Future<String?> getExternalStoragePath() async => externalPath;
}

/// Diagnosis crash HP tertentu (mis. Infinix Smart 8) yang force-close
/// instan tanpa keterangan — jaring pengaman ini menyimpan detail error ke
/// file lokal (JSONL) di folder eksternal khusus app, TANPA izin tambahan,
/// supaya tetap bisa dibaca via File Manager walau app tidak sempat
/// menampilkan UI sama sekali. Lihat docs/HANDOFF.md untuk konteks penuh.
void main() {
  group('CrashLogService.buildEntry (pure)', () {
    test('menghasilkan JSON valid berisi semua field', () {
      final json = CrashLogService.buildEntry(
        error: StateError('contoh error'),
        stack: StackTrace.current,
        time: DateTime(2026, 7, 13, 10, 30),
        context: 'unit-test',
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['waktu'], '2026-07-13T10:30:00.000');
      expect(decoded['context'], 'unit-test');
      expect(decoded['jenis'], 'StateError');
      expect(decoded['pesan'], contains('contoh error'));
      expect(decoded['stackTrace'], isNotEmpty);
    });
  });

  group('CrashLogService.record / readAll / clear (I/O)', () {
    late Directory tempDir;
    late PathProviderPlatform originalPlatform;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pos_crash_log_');
      originalPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPlatform;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('record() menulis 1 baris JSON ke file, readAll() membacanya balik',
        () async {
      await CrashLogService.record(Exception('gagal buka storage'), null,
          context: 'test-context');

      final file = File('${tempDir.path}/${CrashLogService.fileName}');
      expect(file.existsSync(), isTrue);

      final content = await CrashLogService.readAll();
      expect(content, isNotNull);
      expect(content, contains('gagal buka storage'));
      expect(content, contains('test-context'));
    });

    test('record() dipanggil berkali-kali MENAMBAH baris (append), bukan '
        'menimpa', () async {
      await CrashLogService.record(Exception('error pertama'), null,
          context: 'ctx1');
      await CrashLogService.record(Exception('error kedua'), null,
          context: 'ctx2');

      final content = await CrashLogService.readAll();
      final lines =
          content!.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines, hasLength(2));
      expect(content, contains('error pertama'));
      expect(content, contains('error kedua'));
    });

    test('readAll() null bila belum pernah ada crash tercatat', () async {
      final content = await CrashLogService.readAll();
      expect(content, isNull);
    });

    test('clear() menghapus file, readAll() balik null setelahnya', () async {
      await CrashLogService.record(Exception('x'), null);
      expect(await CrashLogService.readAll(), isNotNull);

      await CrashLogService.clear();
      expect(await CrashLogService.readAll(), isNull);
    });

    test('record() TIDAK melempar error walau path_provider gagal (null)',
        () async {
      PathProviderPlatform.instance = _FakePathProvider(null);
      // Tidak boleh throw — ini jaring pengaman, bukan fitur inti.
      await CrashLogService.record(Exception('apa saja'), null);
    });
  });
}
