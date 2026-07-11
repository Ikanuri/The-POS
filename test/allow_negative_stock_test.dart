import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// C-5 — owner harus SELALU bisa override stok minus (konsisten dengan izin
/// lain: override harga, input stok, dst yang semuanya tanpa syarat untuk
/// owner). Sebelumnya owner ikut ke-block sama seperti kasir kalau setting
/// global "allow_negative_stock" OFF, tidak ada bypass khusus owner.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const owner = DeviceIdentity(deviceRole: 'owner');
  const kasir = DeviceIdentity(deviceRole: 'kasir');
  const asisten = DeviceIdentity(deviceRole: 'asisten');

  test('owner SELALU boleh, walau setting global OFF', () async {
    await db.setSetting('allow_negative_stock', '0');
    expect(await resolveAllowNegativeStock(db, owner), isTrue);
  });

  test('kasir mengikuti setting global: OFF → diblokir', () async {
    await db.setSetting('allow_negative_stock', '0');
    expect(await resolveAllowNegativeStock(db, kasir), isFalse);
  });

  test('kasir mengikuti setting global: ON → boleh', () async {
    await db.setSetting('allow_negative_stock', '1');
    expect(await resolveAllowNegativeStock(db, kasir), isTrue);
  });

  test(
      'asisten diblokir jika setting global OFF & izin asisten_stok_minus OFF',
      () async {
    await db.setSetting('allow_negative_stock', '0');
    expect(await resolveAllowNegativeStock(db, asisten), isFalse);
  });

  test(
      'asisten boleh jika izin asisten_stok_minus ON meski setting global OFF',
      () async {
    await db.setSetting('allow_negative_stock', '0');
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('asisten_stok_minus')))
        .write(const KasirPermissionsCompanion(isEnabled: Value(true)));
    expect(await resolveAllowNegativeStock(db, asisten), isTrue);
  });
}
