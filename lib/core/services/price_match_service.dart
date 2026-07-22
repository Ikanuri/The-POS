import '../database/app_database.dart';
import 'price_sync_service.dart';

/// Sync harga induk-cabang (didiskusikan & disepakati 21 Juli — lihat task
/// manager) — fuzzy Levenshtein DIBUANG TOTAL dari keputusan otomatis
/// maupun sbg penentu kandidat tunggal. Data nyata user (2.746 baris induk,
/// 2.775 baris cabang) membuktikan fuzzy pada nama produk pendek (beda cuma
/// varian/ukuran, mis. "cup pop ice uk 12/14/16/18") menghasilkan salah
/// tempel yang TIDAK bisa ditambal dgn menaikkan ambang batas — itu memang
/// fondasi menebak, bukan soal kurang pintar.
///
/// Urutan kepercayaan baru (dari paling pasti):
///  1. Barcode cocok → otomatis (MatchType.barcode).
///  2. `kode_produk` (SKU) sama & UNIK di kedua sisi (katalog masuk MAUPUN
///     produk lokal) → otomatis (MatchType.sku) — warisan clone data lama,
///     BUKAN tebakan. KECUALI produk lokal itu SUDAH punya barcode yang
///     "terlihat resmi" (13 digit) dan BEDA dari barcode katalog yang juga
///     terlihat resmi → itu anomali sungguhan, jangan digabung otomatis,
///     lempar ke [AmbiguousItem] (`AmbiguousReason.kodeConflict`).
///  3. Nama+satuan cocok PERSIS (exact, bukan fuzzy) ke SATU produk lokal →
///     [AmbiguousItem] dgn 1 kandidat (`AmbiguousReason.nameUniqueCandidate`)
///     — UI bisa tawarkan "Terima Semua Kandidat Tunggal" (borongan, sekali
///     klik), TAPI tetap lewat konfirmasi user, bukan auto-terap.
///  4. Nama cocok persis ke LEBIH DARI SATU produk lokal → [AmbiguousItem]
///     dgn banyak kandidat (`AmbiguousReason.nameMultipleCandidates`) — user
///     pilih satu dari daftar, tidak ada yang ditebak duluan.
///  5. Tidak ada kecocokan nama sama sekali → [PriceMatchResult.notFound]
///     (mis. produk khusus toko ini, atau beda ejaan — bukan urusan
///     algoritma ini menebak ejaan).
///
/// Begitu user KONFIRMASI (link) hasil tingkat 2/3/4, aplikasi (di
/// `price_preview_screen.dart`) MENULISKAN barcode katalog sbg alias
/// permanen ke `product_barcodes` produk lokal itu (TIDAK menimpa barcode
/// asli yang sudah ada — ditambah sbg baris non-primary) — supaya sinkron
/// BERIKUTNYA untuk produk itu langsung lompat ke Tingkat 1 (barcode)
/// selamanya, tidak pernah ditebak/ditinjau ulang. Inilah yang menutup
/// akar masalah "harga berubah sendiri padahal sudah fixed": dulu setiap
/// sinkron menebak ulang dari nol tanpa ingatan sama sekali.
enum MatchType { barcode, sku }

enum AmbiguousReason { nameUniqueCandidate, nameMultipleCandidates, kodeConflict }

class PriceMatchResult {
  const PriceMatchResult({
    required this.matched,
    required this.notFound,
    required this.ambiguous,
    required this.log,
  });
  final List<MatchedItem> matched;
  final List<PriceCatalogItem> notFound;
  final List<AmbiguousItem> ambiguous;
  final List<String> log;
}

class MatchedItem {
  MatchedItem({
    required this.catalogItem,
    required this.localProductId,
    required this.localProductUnitId,
    required this.localProductName,
    required this.localPrice,
    required this.localCostPrice,
    required this.matchType,
    this.linkBarcode,
    this.selected = true,
  });

  final PriceCatalogItem catalogItem;
  final String localProductId;
  final String localProductUnitId;
  final String localProductName;
  final int localPrice;
  final int localCostPrice;
  final MatchType matchType;

  /// Barcode katalog yang perlu ditulis sbg alias permanen ke produk lokal
  /// ini saat diterapkan (non-null HANYA utk [MatchType.sku] — cocok via
  /// barcode langsung tidak perlu menulis apa pun, sudah identik).
  final String? linkBarcode;
  bool selected;

  bool get priceChanged => catalogItem.price != localPrice;
  bool get costChanged => catalogItem.costPrice != localCostPrice;
  bool get hasChanges => priceChanged || costChanged;
}

/// Satu kandidat produk lokal utk sebuah item katalog yang belum pasti
/// (lihat [AmbiguousItem.candidates]) — bisa 1 (disarankan kuat, tinggal
/// konfirmasi) atau banyak (user pilih sendiri).
class AmbiguousCandidate {
  const AmbiguousCandidate({
    required this.productId,
    required this.productUnitId,
    required this.productName,
    required this.price,
    required this.costPrice,
  });
  final String productId;
  final String productUnitId;
  final String productName;
  final int price;
  final int costPrice;
}

class AmbiguousItem {
  AmbiguousItem({
    required this.catalogItem,
    required this.candidates,
    required this.reason,
  });

  final PriceCatalogItem catalogItem;
  final List<AmbiguousCandidate> candidates;
  final AmbiguousReason reason;
}

class PriceMatchService {
  PriceMatchService._();

  /// [barcodeOnly] — Item 35(opsional): mode "sinkron via barcode saja"
  /// utk toko besar/data yang kode produknya (SKU) tidak bisa dipercaya
  /// sama sekali. Kalau true, SKU & nama dilewati sepenuhnya — item tanpa
  /// barcode-cocok langsung `notFound` (bukan ditebak lewat sinyal yang
  /// lebih lemah). Paling aman utk katalog besar/data mentah yang kode
  /// produknya diisi nama satuan (lihat Item 35 di PLAN.md/HANDOFF).
  static Future<PriceMatchResult> match({
    required AppDatabase db,
    required List<PriceCatalogItem> catalog,
    bool barcodeOnly = false,
  }) async {
    final matched = <MatchedItem>[];
    final notFound = <PriceCatalogItem>[];
    final ambiguous = <AmbiguousItem>[];
    final log = <String>[];

    log.add('=== MATCH START: ${catalog.length} catalog items ==='
        '${barcodeOnly ? ' (mode barcode-saja)' : ''}');

    final allProducts = await db.searchProducts('');
    log.add('Produk lokal aktif: ${allProducts.length}');

    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    // kode_produk hanya dipercaya sbg Tingkat 2 bila unik di KEDUA sisi —
    // hitung frekuensinya di sisi KATALOG (sisi lokal dicek per-item lewat
    // allProducts di _tryMatch, tapi sisi katalog perlu dihitung sekali di
    // sini krn baru terlihat setelah seluruh daftar masuk).
    final catalogCodeCount = <String, int>{};
    for (final item in catalog) {
      final k = item.kodeProduk?.trim().toLowerCase();
      if (k != null && k.isNotEmpty) {
        catalogCodeCount[k] = (catalogCodeCount[k] ?? 0) + 1;
      }
    }

    // Nama produk lokal (persis, bukan fuzzy) → daftar produk dgn nama itu.
    // Dipakai Tingkat 3/4 (exact-name candidates).
    final localByName = <String, List<Product>>{};
    for (final p in allProducts) {
      localByName.putIfAbsent(p.name.trim().toLowerCase(), () => []).add(p);
    }

    for (final item in catalog) {
      if (barcodeOnly) {
        final result = await _tryMatchBarcodeOnly(db, item, allProducts, log);
        if (result != null) {
          matched.add(result);
          continue;
        }
        log.add('  → Mode barcode-saja: tidak cocok → notFound (SKU/nama '
            'dilewati)');
        notFound.add(item);
        continue;
      }

      final (skuMatch, skuConflict) = await _tryMatch(
          db, item, allProducts, typeNameById, catalogCodeCount, log);
      if (skuMatch != null) {
        matched.add(skuMatch);
        continue;
      }
      if (skuConflict != null) {
        ambiguous.add(skuConflict);
        continue;
      }

      final candidates = localByName[item.productName.trim().toLowerCase()];
      if (candidates == null || candidates.isEmpty) {
        log.add('  → Tidak ada produk lokal bernama sama → notFound');
        notFound.add(item);
        continue;
      }

      final built = <AmbiguousCandidate>[];
      for (final p in candidates) {
        final units = await db.getProductUnits(p.id);
        if (units.isEmpty) continue;
        final unit = _resolveUnit(units, typeNameById, item.unitTypeName);
        final tiers = await db.getPriceTiers(unit.id);
        final baseTier =
            tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
        built.add(AmbiguousCandidate(
          productId: p.id,
          productUnitId: unit.id,
          productName: p.name,
          price: baseTier?.price ?? 0,
          costPrice: baseTier?.costPrice ?? 0,
        ));
      }
      if (built.isEmpty) {
        log.add('  → Nama cocok tapi tidak ada unit tersedia → notFound');
        notFound.add(item);
        continue;
      }
      final reason = built.length == 1
          ? AmbiguousReason.nameUniqueCandidate
          : AmbiguousReason.nameMultipleCandidates;
      log.add('  → Nama cocok persis (${built.length} kandidat) → '
          '${reason == AmbiguousReason.nameUniqueCandidate ? "usulan tunggal" : "AMBIGU, perlu pilih"}');
      ambiguous.add(AmbiguousItem(
          catalogItem: item, candidates: built, reason: reason));
    }

    log.add('=== MATCH DONE: ${matched.length} cocok, '
        '${notFound.length} baru, ${ambiguous.length} perlu tinjau ===');

    return PriceMatchResult(
      matched: matched,
      notFound: notFound,
      ambiguous: ambiguous,
      log: log,
    );
  }

  static ProductUnit _resolveUnit(
    List<ProductUnit> units,
    Map<int, String> typeNameById,
    String wantTypeName,
  ) {
    final want = wantTypeName.trim().toLowerCase();
    if (want.isNotEmpty) {
      for (final u in units) {
        final tn =
            (u.unitTypeId != null ? typeNameById[u.unitTypeId!] : null) ?? '';
        if (tn.trim().toLowerCase() == want) return u;
      }
    }
    return units.where((u) => u.isBaseUnit).firstOrNull ?? units.first;
  }

  /// Seperti [_resolveUnit] tapi TANPA fallback ke base unit bila satuan yang
  /// diminta tidak ada — kembalikan null. Dipakai jalur auto-match SKU yang
  /// harus ketat (SKU sinyal lemah antar-toko; wajib satuannya benar-benar
  /// ada agar tidak salah tempel harga). Bila katalog tidak menyertakan nama
  /// satuan (`wantTypeName` kosong), tak bisa lebih ketat → pakai base unit.
  static ProductUnit? _resolveUnitStrict(
    List<ProductUnit> units,
    Map<int, String> typeNameById,
    String wantTypeName,
  ) {
    final want = wantTypeName.trim().toLowerCase();
    if (want.isEmpty) {
      return units.where((u) => u.isBaseUnit).firstOrNull ?? units.firstOrNull;
    }
    for (final u in units) {
      final tn =
          (u.unitTypeId != null ? typeNameById[u.unitTypeId!] : null) ?? '';
      if (tn.trim().toLowerCase() == want) return u;
    }
    return null;
  }

  /// Barcode 13-digit numerik — sinyal "terlihat seperti barcode pabrik
  /// resmi" (dibuktikan dari data nyata: barcode yang benar-benar cocok
  /// antar toko 74% panjang 13, yang ternyata konflik/fabrikasi 82% panjang
  /// 8). Dipakai HANYA utk memutuskan kapan konflik SKU vs barcode adalah
  /// anomali sungguhan yg layak tinjauan manual (bukan validasi checksum
  /// GS1 — checksum tetap valid pada barcode buatan sendiri, jadi bukan
  /// bukti kuat sendirian, cuma sinyal tambahan yg terbukti berkorelasi).
  static bool _looksOfficialBarcode(String bc) {
    final t = bc.trim();
    return t.length == 13 && RegExp(r'^\d{13}$').hasMatch(t);
  }

  /// Return `(matched, null)` bila cocok via barcode/SKU, `(null, ambiguous)`
  /// bila SKU cocok tapi kena anomali konflik-barcode (perlu tinjauan
  /// eksplisit, JANGAN jatuh diam-diam ke pencocokan nama generik supaya
  /// UI bisa tampilkan alasan spesifiknya), atau `(null, null)` bila kedua
  /// sinyal ini tidak berlaku sama sekali (caller lanjut ke pencocokan
  /// nama-persis).
  static Future<(MatchedItem?, AmbiguousItem?)> _tryMatch(
    AppDatabase db,
    PriceCatalogItem item,
    List<Product> allProducts,
    Map<int, String> typeNameById,
    Map<String, int> catalogCodeCount,
    List<String> log,
  ) async {
    log.add('[${item.productName}] catalog: price=${item.price}, '
        'cost=${item.costPrice}, barcode=${item.barcode ?? "null"}, '
        'sku=${item.kodeProduk ?? "null"}, unit="${item.unitTypeName}"');

    // 1. Match by barcode
    if (item.barcode != null && item.barcode!.isNotEmpty) {
      final bc = await db.lookupBarcode(item.barcode!);
      if (bc != null) {
        final unit = await (db.select(db.productUnits)
              ..where((t) => t.id.equals(bc.productUnitId)))
            .getSingleOrNull();
        if (unit != null) {
          final product = allProducts.where((p) => p.id == unit.productId).firstOrNull;
          if (product != null) {
            final tiers = await db.getPriceTiers(unit.id);
            final tierCount = tiers.where((t) => t.minQty == 1).length;
            log.add('  → Barcode match: unit=${_short(unit.id)}, '
                'product="${product.name}"');
            log.add('    Tiers minQty=1: $tierCount buah → '
                '${tiers.where((t) => t.minQty == 1).map((t) => 'id=${_short(t.id)} price=${t.price} cost=${t.costPrice}').join(' | ')}');
            final baseTier =
                tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
            log.add('    baseTier dipilih: id=${_short(baseTier?.id ?? "?")} '
                'price=${baseTier?.price ?? 0} cost=${baseTier?.costPrice ?? 0}');
            if (tierCount > 1) {
              log.add('    ⚠ DUPLIKAT TIER! $tierCount tier minQty=1 untuk unit ini');
            }
            return (
              MatchedItem(
                catalogItem: item,
                localProductId: product.id,
                localProductUnitId: unit.id,
                localProductName: product.name,
                localPrice: baseTier?.price ?? 0,
                localCostPrice: baseTier?.costPrice ?? 0,
                matchType: MatchType.barcode,
              ),
              null
            );
          } else {
            log.add('  → Barcode ditemukan tapi produk tidak di allProducts '
                '(inactive?) productId=${unit.productId}');
          }
        } else {
          log.add('  → Barcode ditemukan tapi unit hilang: ${bc.productUnitId}');
        }
      } else {
        log.add('  → Barcode "${item.barcode}" tidak ada di DB');
      }
    }

    // 2. Match by kode_produk (SKU/nomor lama warisan clone) — HANYA aman
    // bila kode UNIK di KEDUA sisi (lokal maupun katalog masuk) & satuan
    // cocok. Kode yg tabrakan di salah satu sisi = tidak bisa dipercaya
    // sendirian, jatuh ke pencocokan nama (poin 3/4 di bawah).
    if (item.kodeProduk != null && item.kodeProduk!.isNotEmpty) {
      final skuLower = item.kodeProduk!.trim().toLowerCase();
      final uniqueInCatalog = (catalogCodeCount[skuLower] ?? 0) <= 1;
      final skuMatches = allProducts
          .where((p) => (p.kodeProduk ?? '').trim().toLowerCase() == skuLower)
          .toList();

      if (!uniqueInCatalog) {
        log.add('  → SKU "${item.kodeProduk}" tidak unik di KATALOG MASUK '
            '(dipakai ${catalogCodeCount[skuLower]} baris) → tidak dipercaya, '
            'coba pencocokan nama');
      } else if (skuMatches.length > 1) {
        // Tabrakan SKU: kode_produk tidak unik (mis. banyak produk berkode
        // nama satuan "Dos"/"Pak"/"Bal"). Ambil-pertama-sembarang dulu bikin
        // item nyasar ke produk tak berhubungan & harga saling-timpa tiap
        // sync (non-konvergen). Jangan tebak — biarkan pencocokan nama yang
        // tangani (masuk tab "Perlu Ditinjau" utk konfirmasi manual).
        log.add('  → SKU "${item.kodeProduk}" cocok ke ${skuMatches.length} '
            'produk lokal (TABRAKAN, kode tidak unik) → tidak auto-match');
      } else if (skuMatches.length == 1) {
        final product = skuMatches.first;
        final units = await db.getProductUnits(product.id);
        if (units.isEmpty) {
          log.add('  → SKU match tapi tidak ada unit untuk product "${product.name}"');
        } else {
          // Perketat: satuan katalog HARUS ada di produk lokal. Cegah item
          // spt "76 12/bal" nyasar ke "Atira 2000" hanya karena kebetulan
          // berkode "bal" padahal tak punya satuan "Bal".
          final unit = _resolveUnitStrict(units, typeNameById, item.unitTypeName);
          if (unit == null) {
            log.add('  → SKU match "${product.name}" tapi satuan '
                '"${item.unitTypeName}" tidak ada di produk itu → tolak, '
                'coba pencocokan nama');
          } else {
            // Cek anomali: produk lokal sudah punya barcode "resmi" yg BEDA
            // dari barcode katalog yg juga "resmi" → dua barcode pabrik asli
            // berbeda utk kode yg sama, itu anomali sungguhan, jangan
            // digabung otomatis — lempar ke tinjauan manual.
            final localBarcodes = await (db.select(db.productBarcodes)
                  ..where((t) => t.productUnitId.equals(unit.id)))
                .get();
            final localOfficial = localBarcodes
                .map((b) => b.barcode)
                .where(_looksOfficialBarcode)
                .toList();
            final catalogBc = item.barcode?.trim() ?? '';
            final catalogOfficial =
                catalogBc.isNotEmpty && _looksOfficialBarcode(catalogBc);
            final conflict = catalogOfficial &&
                localOfficial.isNotEmpty &&
                !localOfficial.contains(catalogBc);

            final tiers = await db.getPriceTiers(unit.id);
            final baseTier = tiers.where((t) => t.minQty == 1).firstOrNull ??
                tiers.firstOrNull;

            if (conflict) {
              log.add('  → SKU cocok "${product.name}" TAPI barcode lokal '
                  '($localOfficial) vs katalog ($catalogBc) sama-sama '
                  'terlihat resmi & BEDA → anomali sungguhan, tinjauan '
                  'manual (BUKAN auto-match)');
              return (
                null,
                AmbiguousItem(
                  catalogItem: item,
                  candidates: [
                    AmbiguousCandidate(
                      productId: product.id,
                      productUnitId: unit.id,
                      productName: product.name,
                      price: baseTier?.price ?? 0,
                      costPrice: baseTier?.costPrice ?? 0,
                    ),
                  ],
                  reason: AmbiguousReason.kodeConflict,
                ),
              );
            }

            log.add('  → SKU match: unit=${_short(unit.id)}, '
                'product="${product.name}", ${units.length} units total');
            log.add('    baseTier dipilih: id=${_short(baseTier?.id ?? "?")} '
                'price=${baseTier?.price ?? 0}');
            return (
              MatchedItem(
                catalogItem: item,
                localProductId: product.id,
                localProductUnitId: unit.id,
                localProductName: product.name,
                localPrice: baseTier?.price ?? 0,
                localCostPrice: baseTier?.costPrice ?? 0,
                matchType: MatchType.sku,
                // Barcode katalog (kalau ada) ditulis sbg alias permanen saat
                // diterapkan — supaya sync berikutnya utk produk ini lompat
                // ke Tingkat 1 (barcode) selamanya, tak perlu SKU lagi.
                linkBarcode: catalogBc.isNotEmpty ? catalogBc : null,
              ),
              null
            );
          }
        }
      } else {
        log.add('  → SKU "${item.kodeProduk}" tidak cocok');
      }
    }

    return (null, null);
  }

  /// Item 35(opsional) — mode "sinkron via barcode saja". Sama persis
  /// dengan blok barcode di [_tryMatch] (sinyal paling andal, deterministik
  /// per unit), TAPI berhenti di situ — TIDAK jatuh ke SKU/nama sama
  /// sekali. Dipakai saat data toko sumber tidak bisa dipercaya SKU-nya
  /// (mis. `kode_produk` diisi nama satuan seperti "Dos"/"Pak").
  static Future<MatchedItem?> _tryMatchBarcodeOnly(
    AppDatabase db,
    PriceCatalogItem item,
    List<Product> allProducts,
    List<String> log,
  ) async {
    log.add('[${item.productName}] catalog: price=${item.price}, '
        'barcode=${item.barcode ?? "null"} (mode barcode-saja)');

    if (item.barcode == null || item.barcode!.isEmpty) {
      log.add('  → Tanpa barcode → notFound (SKU/nama dilewati)');
      return null;
    }

    final bc = await db.lookupBarcode(item.barcode!);
    if (bc == null) {
      log.add('  → Barcode "${item.barcode}" tidak ada di DB');
      return null;
    }
    final unit = await (db.select(db.productUnits)
          ..where((t) => t.id.equals(bc.productUnitId)))
        .getSingleOrNull();
    if (unit == null) {
      log.add('  → Barcode ditemukan tapi unit hilang: ${bc.productUnitId}');
      return null;
    }
    final product = allProducts.where((p) => p.id == unit.productId).firstOrNull;
    if (product == null) {
      log.add('  → Barcode ditemukan tapi produk tidak di allProducts '
          '(inactive?) productId=${unit.productId}');
      return null;
    }
    final tiers = await db.getPriceTiers(unit.id);
    final baseTier =
        tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
    log.add('  → Barcode match: unit=${_short(unit.id)}, '
        'product="${product.name}"');
    return MatchedItem(
      catalogItem: item,
      localProductId: product.id,
      localProductUnitId: unit.id,
      localProductName: product.name,
      localPrice: baseTier?.price ?? 0,
      localCostPrice: baseTier?.costPrice ?? 0,
      matchType: MatchType.barcode,
    );
  }

  static String _short(String uuid) =>
      uuid.length > 8 ? uuid.substring(0, 8) : uuid;
}
