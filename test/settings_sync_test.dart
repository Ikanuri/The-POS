import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Temuan audit 11 Agt 2026: `app_settings`, `payment_methods`, dan
/// `employees` TIDAK PERNAH ikut sync sama sekali.
///
/// Yang paling berbahaya: aturan poin loyalti (`loyalty_points_per`,
/// `loyalty_point_threshold`) dibaca SAAT CHECKOUT, jadi nota bernilai sama
/// bisa dapat poin BERBEDA tergantung device — padahal
/// `loyalty_point_ledger`-nya sendiri ikut tersync, jadi inkonsistensinya
/// masuk ke data bersama.
///
/// TAPI `app_settings` TIDAK BOLEH di-dump bulat-bulat: isinya bercampur
/// dgn identitas/state device (`store_key`, `device_code`, watermark sync).
/// Karena itu pakai ALLOWLIST, dan disaring di KEDUA sisi.
late AppDatabase db;

void main() {
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('dump (sisi host)', () {
    test('setting toko yang di-allowlist IKUT dump host->klien', () async {
      await db.setSetting('loyalty_points_per', '1000');
      await db.setSetting('allow_negative_stock', '1');
      await db.setSetting('store_address', 'Jl. Mawar 1');

      final dump = await db.dumpSince(DateTime(2000));
      final keys = (dump['app_settings'] ?? [])
          .map((r) => r['key'] as String)
          .toSet();

      expect(keys, containsAll(<String>[
        'loyalty_points_per',
        'allow_negative_stock',
        'store_address',
      ]));
    });

    test('IDENTITAS/STATE DEVICE tidak pernah ikut dump', () async {
      await db.setSetting('store_key', 'RAHASIA');
      await db.setSetting('store_uuid', 'uuid-toko');
      await db.setSetting('device_code', 'K1');
      await db.setSetting('device_role', 'owner');
      await db.setSetting('last_archive_date', '2026-01-01');
      await db.setSetting('store_name', 'Toko Berkah');

      final dump = await db.dumpSince(DateTime(2000));
      final keys = (dump['app_settings'] ?? [])
          .map((r) => r['key'] as String)
          .toSet();

      expect(keys, contains('store_name'), reason: 'yang ini memang boleh');
      for (final forbidden in [
        'store_key',
        'store_uuid',
        'device_code',
        'device_role',
        'last_archive_date',
      ]) {
        expect(keys, isNot(contains(forbidden)),
            reason: '$forbidden identitas/state device — kalau ikut, klien '
                'tertimpa identitasnya sendiri');
      }
    });

    test('setting TIDAK ikut naik saat klien mengirim ke host', () async {
      await db.setSetting('store_name', 'Toko Berkah');
      final dump = await db.dumpSince(DateTime(2000), includeMasterData: false);
      expect(dump['app_settings'], isNull,
          reason: 'setting toko = master data owner, tetap SATU ARAH');
    });

    test('payment_methods & employees ikut dump host->klien', () async {
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
            id: 'pm1',
            type: 'bank',
            name: 'BRI',
          ));
      await db.into(db.employees).insert(
          EmployeesCompanion.insert(id: 'e1', name: 'Budi'));

      final dump = await db.dumpSince(DateTime(2000));
      // `payment_methods` sudah berisi metode bawaan dari `_seedDefaults`,
      // jadi cek KEBERADAAN baris yang baru ditambah, bukan jumlah total.
      expect(
          (dump['payment_methods'] ?? []).map((r) => r['id']), contains('pm1'));
      expect((dump['employees'] ?? []).map((r) => r['id']), contains('e1'));
    });
  });

  group('merge (sisi penerima)', () {
    test('key di luar allowlist DITOLAK walau ada di payload', () async {
      final n = await db.mergeRows('app_settings', [
        {'key': 'store_name', 'value': 'Toko Baru', 'updated_at': 111},
        {'key': 'store_key', 'value': 'DIBAJAK', 'updated_at': 111},
        {'key': 'device_code', 'value': 'X9', 'updated_at': 111},
      ], false);

      expect(n, 1, reason: 'hanya store_name yang diterima');
      expect(await db.getSetting('store_name'), 'Toko Baru');
      expect(await db.getSetting('store_key'), isNull,
          reason: 'guard sisi penerima wajib berdiri sendiri — jangan '
              'bergantung pada dump pengirim yang bisa saja tidak jujur');
      expect(await db.getSetting('device_code'), isNull);
    });

    test('payload berisi HANYA key terlarang -> tidak ada yang ditulis',
        () async {
      final n = await db.mergeRows('app_settings', [
        {'key': 'store_key', 'value': 'DIBAJAK', 'updated_at': 111},
      ], false);
      expect(n, 0);
      expect(await db.getSetting('store_key'), isNull);
    });
  });

  group('guard arah sync', () {
    test('tabel setting boleh di-merge klien dari host', () {
      expect(LanSyncService.clientMergeableTables, contains('app_settings'));
      expect(LanSyncService.clientMergeableTables, contains('payment_methods'));
      expect(LanSyncService.clientMergeableTables, contains('employees'));
    });

    test('setting BUKAN tabel dua-arah — host tetap menolaknya dari klien',
        () {
      expect(LanSyncService.sharedTables, isNot(contains('app_settings')));
      expect(LanSyncService.appendOnlyTables,
          isNot(contains('app_settings')));
    });
  });
}
