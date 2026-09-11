import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Kelas bug SAMA dgn `product_deactivate_sync_reactive_test.dart` &
/// `tutup_buku_stock_stream_reactive_test.dart`, lokasi BERBEDA:
/// `applyProductProposals` menulis 5 tabel (products/product_units/
/// price_tiers/alt_prices/product_barcodes) lewat `customStatement`/
/// `customInsert` raw SQL TANPA parameter `updates:` — data DI DB sudah
/// benar setelah owner approve usulan kasir (dibuktikan test lain, mis.
/// `proposal_price_change_apply_test.dart`, semua one-shot query), tapi
/// `StreamProvider`/`.watch()` (mis. `watchBaseUnitPrices()`, dipakai layar
/// produk/kasir utk harga satuan dasar) TIDAK tahu tabel `price_tiers`
/// berubah — jadi tidak auto-refresh, layar yg sedang terbuka menampilkan
/// harga STALE sampai di-restart manual. Test ini membuktikan reaktivitas
/// via `.listen()` sungguhan ke `watchBaseUnitPrices()`, bukan cuma query
/// ulang.
void main() {
  test(
      'watchBaseUnitPrices() (Stream live) ikut ter-refresh otomatis setelah '
      'applyProductProposals — bukan cuma query one-shot', () async {
    final host = AppDatabase(NativeDatabase.memory());
    final asisten = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await host.close();
      await asisten.close();
    });

    Future<void> seedProduct(AppDatabase db,
        {required int price,
        required String tierId,
        bool locallyModified = false}) async {
      await db.saveProduct(
        product: ProductsCompanion.insert(
            id: 'P', name: 'Gula', locallyModified: Value(locallyModified)),
        units: [
          ProductUnitsCompanion.insert(
              id: 'U',
              productId: 'P',
              unitTypeId: const Value(1),
              isBaseUnit: const Value(true),
              ratioToBase: const Value(1.0)),
        ],
        tiersByUnitTempId: {
          'U': [
            PriceTiersCompanion.insert(
                id: tierId, productUnitId: 'U', price: price)
          ],
        },
        barcodesByUnitTempId: const {},
      );
    }

    // Owner & asisten mula-mula sama: tier 't1' harga 5000.
    await seedProduct(host, price: 5000, tierId: 't1');
    await seedProduct(asisten, price: 5000, tierId: 't1');

    // Subscribe ke stream LIVE di host SEBELUM approve.
    final emissions = <int?>[];
    final sub = host.watchBaseUnitPrices().listen((m) => emissions.add(m['P']));
    addTearDown(sub.cancel);

    // Tunggu emission awal (harga 5000).
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emissions, isNotEmpty);
    expect(emissions.last, 5000);
    final emissionCountBeforeApprove = emissions.length;

    // Asisten ubah harga → tier baru 't2' 7000 (id regenerasi), tandai usulan.
    await seedProduct(asisten, price: 7000, tierId: 't2', locallyModified: true);

    // Owner terima usulan & approve — persis alur nyata.
    final proposal = await asisten.dumpLocalProposals();
    final applied = await host.applyProductProposals(proposal, {'P'});
    expect(applied, greaterThan(0));

    // Beri waktu stream Drift meng-emit ulang (async gap sungguhan).
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(emissions.length, greaterThan(emissionCountBeforeApprove),
        reason: 'watchBaseUnitPrices() HARUS meng-emit lagi setelah '
            'applyProductProposals mengubah tabel price_tiers — kalau '
            'jumlah emission tidak bertambah, berarti Drift tidak tahu '
            'tabel ini berubah (customStatement/customInsert tanpa '
            '`updates:`) dan UI owner akan terlihat "tidak berubah" walau '
            'data DB sudah benar sampai di-restart.');
    expect(emissions.last, 7000,
        reason: 'nilai stream TERBARU harus mencerminkan harga baru (7000) '
            'setelah approve, bukan cuma "ada emission baru".');
  });
}
