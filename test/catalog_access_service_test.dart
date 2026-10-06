import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_access_service.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 cocok dgn vektor uji resmi (RFC 7914/6070 style)',
      () {
    // "password"/"salt", 1 putaran dan 4096 putaran, dkLen 32.
    expect(CatalogAccessService.pbkdf2Hex('password', 'salt', 1),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(CatalogAccessService.pbkdf2Hex('password', 'salt', 4096),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
  });

  test('normalizeCode & generateCode', () {
    expect(CatalogAccessService.normalizeCode(' ab-cd 12 '), 'ABCD12');
    final code = CatalogAccessService.generateCode(Random(1));
    expect(code, matches(RegExp(r'^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$')));
    expect(CatalogAccessService.generateCode(Random(2)), isNot(code));
  });

  test('rotateCode simpan hash, ganti kode lama, accessJson tanpa kode/nama',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.into(db.customers).insert(CustomersCompanion.insert(
        id: 'C1', name: 'Bu Sari', phone: const Value('0812')));
    await db.into(db.customers).insert(CustomersCompanion.insert(
        id: 'C2', name: 'Pak Budi', isActive: const Value(false)));
    expect(await CatalogAccessService.accessJson(db), isNull);

    final c1 = await CatalogAccessService.rotateCode(db, 'C1');
    await CatalogAccessService.rotateCode(db, 'C2'); // pelanggan nonaktif
    expect(await CatalogAccessService.codeFor(db, 'C1'), c1);
    final a = (await CatalogAccessService.accessJson(db))!;
    final hashes = a['hashes'] as List;
    expect(hashes, hasLength(1), reason: 'pelanggan nonaktif tidak ikut');
    expect(
        hashes.single,
        CatalogAccessService.pbkdf2Hex(CatalogAccessService.normalizeCode(c1),
            a['salt'] as String, a['iters'] as int));
    expect(a.toString(), isNot(contains(c1)));
    expect(a.toString(), isNot(contains('Sari')));

    final c1b = await CatalogAccessService.rotateCode(db, 'C1');
    expect(c1b, isNot(c1));
    final a2 = (await CatalogAccessService.accessJson(db))!;
    expect((a2['hashes'] as List).single, isNot(hashes.single),
        reason: 'kode lama otomatis tidak berlaku lagi');

    await CatalogAccessService.revokeCode(db, 'C1');
    expect(await CatalogAccessService.codeFor(db, 'C1'), isNull);
    expect(await CatalogAccessService.accessJson(db), isNull);
  });

  test('jam buka: default mati, simpan/muat, hoursJson memuat zona', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    expect((await CatalogAccessService.loadHours(db)).enabled, isFalse);
    expect(await CatalogAccessService.hoursJson(db), isNull);

    await CatalogAccessService.saveHours(
        db,
        const CatalogHours(
            enabled: true, openMinutes: 7 * 60 + 30, closeMinutes: 21 * 60));
    final h = await CatalogAccessService.loadHours(db);
    expect(h.enabled, isTrue);
    expect(CatalogHours.hhmm(h.openMinutes), '07:30');
    final j = (await CatalogAccessService.hoursJson(db,
        tzOffset: const Duration(hours: 8)))!;
    expect(j['tz'], 480);
    expect(j['open'], 450);
    expect(j['forced'], isFalse);

    await CatalogAccessService.saveHours(
        db, h.copyWith(enabled: false, forcedClosed: true));
    expect((await CatalogAccessService.hoursJson(db))!['forced'], isTrue);
  });
}
