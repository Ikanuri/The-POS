import '../database/app_database.dart';
import '../models/cart_item.dart';
import 'order_page_service.dart';
import 'price_service.dart';

/// Parser sisi kasir untuk teks pesanan pelanggan yang dihasilkan oleh
/// [OrderPageService] — dipakai fitur "Tempel Pesanan" di layar kasir.
///
/// Prinsip penting: harga & HPP **selalu di-resolve ulang dari DB lokal saat
/// ini juga** (bukan dari angka yang mungkin tertulis di teks pesanan) —
/// katalog HTML yang dikirim ke pelanggan bisa jadi sudah beberapa hari, tapi
/// transaksi yang tersimpan tetap memakai harga terkini. Barang yang sudah
/// dihapus/dinonaktifkan sejak katalog dibuat otomatis masuk [ParsedOrder.notFound].
class OrderParserService {
  OrderParserService._();

  static final RegExp _machineLine =
      RegExp('${OrderPageService.machineCodePrefix}(.+)\$', multiLine: true);
  static final RegExp _nameLine = RegExp(r'^Nama:\s*(.+)$', multiLine: true);
  static final RegExp _phoneLine = RegExp(r'^HP:\s*(.+)$', multiLine: true);
  static final RegExp _noteLine = RegExp(r'^Catatan:\s*(.+)$', multiLine: true);

  static Future<ParsedOrder> parse({
    required AppDatabase db,
    required String text,
  }) async {
    final match = _machineLine.firstMatch(text);
    if (match == null) {
      return const ParsedOrder(
        items: [],
        notFound: [],
        customerName: null,
        customerPhone: null,
        note: null,
        hasMachineCode: false,
      );
    }

    final priceService = PriceService(db);
    final items = <ParsedOrderItem>[];
    final notFound = <String>[];
    // Baris yang sama (unitId sama) muncul dobel bila teks ditempel dua kali
    // secara tak sengaja — gabungkan qty-nya alih-alih menambah baris dobel
    // di keranjang.
    final seenAt = <String, int>{};

    final pairs = match.group(1)!.trim().split(';');
    for (final raw in pairs) {
      final pair = raw.trim();
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) {
        notFound.add(pair);
        continue;
      }
      final unitId = pair.substring(0, eq).trim();
      final rest = pair.substring(eq + 1).trim();
      // Item 26a — segmen catatan opsional setelah qty: "qty:catatan"
      // (catatan ter-encodeURIComponent di sisi HTML, jadi TIDAK pernah
      // mengandung ':' mentah — aman split di ':' PERTAMA).
      final colonIdx = rest.indexOf(':');
      final qtyStr = colonIdx == -1 ? rest : rest.substring(0, colonIdx);
      final qty = double.tryParse(qtyStr);
      if (qty == null || qty <= 0) {
        notFound.add(pair);
        continue;
      }
      String? itemNote;
      if (colonIdx != -1 && colonIdx + 1 < rest.length) {
        try {
          itemNote = Uri.decodeComponent(rest.substring(colonIdx + 1));
        } catch (_) {
          itemNote = null;
        }
      }

      final unit = await (db.select(db.productUnits)
            ..where((t) => t.id.equals(unitId)))
          .getSingleOrNull();
      if (unit == null) {
        notFound.add(unitId);
        continue;
      }
      final product = await (db.select(db.products)
            ..where((t) => t.id.equals(unit.productId)))
          .getSingleOrNull();
      if (product == null || !product.isActive) {
        notFound.add(unitId);
        continue;
      }

      if (seenAt.containsKey(unitId)) {
        final idx = seenAt[unitId]!;
        final prev = items[idx];
        final newQty = prev.qty + qty;
        final reResolved =
            await priceService.resolvePrice(productUnitId: unitId, qty: newQty);
        items[idx] = ParsedOrderItem(
          productId: prev.productId,
          productUnitId: prev.productUnitId,
          productName: prev.productName,
          unitName: prev.unitName,
          qty: newQty,
          price: reResolved.price,
          costPrice: reResolved.costPrice,
          isVariant: prev.isVariant,
          parentProductId: prev.parentProductId,
          // Baris sama muncul dobel (tempel 2x) — catatan dari kemunculan
          // TERAKHIR yang dipakai (bukan digabung, ambigu kalau beda).
          itemNote: itemNote,
        );
        continue;
      }

      final unitType = await (db.select(db.unitTypes)
            ..where((t) => t.id.equals(unit.unitTypeId ?? 1)))
          .getSingleOrNull();
      final resolved =
          await priceService.resolvePrice(productUnitId: unitId, qty: qty);

      seenAt[unitId] = items.length;
      items.add(ParsedOrderItem(
        productId: product.id,
        productUnitId: unitId,
        productName: product.name,
        unitName: unitType?.name ?? 'Satuan',
        qty: qty,
        price: resolved.price,
        costPrice: resolved.costPrice,
        isVariant: product.parentProductId != null,
        parentProductId: product.parentProductId,
        itemNote: itemNote,
      ));
    }

    final name = _nameLine.firstMatch(text)?.group(1)?.trim();
    final phone = _phoneLine.firstMatch(text)?.group(1)?.trim();
    final note = _noteLine.firstMatch(text)?.group(1)?.trim();

    return ParsedOrder(
      items: items,
      notFound: notFound,
      customerName: (name == null || name.isEmpty || name == '-') ? null : name,
      customerPhone:
          (phone == null || phone.isEmpty || phone == '-') ? null : phone,
      note: (note == null || note.isEmpty) ? null : note,
      hasMachineCode: true,
    );
  }
}

/// Satu baris hasil parsing yang berhasil dicocokkan ke produk lokal.
class ParsedOrderItem {
  const ParsedOrderItem({
    required this.productId,
    required this.productUnitId,
    required this.productName,
    required this.unitName,
    required this.qty,
    required this.price,
    required this.costPrice,
    required this.isVariant,
    this.parentProductId,
    this.itemNote,
  });

  final String productId;
  final String productUnitId;
  final String productName;
  final String unitName;
  final double qty;
  final int price;
  final int costPrice;
  final bool isVariant;
  final String? parentProductId;

  /// Catatan per-produk dari pelanggan (Item 26a), mis. "yang matang".
  final String? itemNote;

  int get subtotal => (price * qty).round();

  /// Konversi ke [CartItem] siap masuk `cartProvider`. `barcode` sengaja
  /// null — tempel-pesanan tidak melalui jalur scan barcode.
  CartItem toCartItem() => CartItem(
        productId: productId,
        productUnitId: productUnitId,
        productName: productName,
        unitName: unitName,
        qty: qty,
        price: price,
        originalPrice: price,
        costPrice: costPrice,
        parentProductId: parentProductId,
        isVariant: isVariant,
        itemNote: itemNote,
      );
}

/// Hasil parsing teks pesanan.
class ParsedOrder {
  const ParsedOrder({
    required this.items,
    required this.notFound,
    required this.customerName,
    required this.customerPhone,
    required this.note,
    required this.hasMachineCode,
  });

  /// Baris yang berhasil dicocokkan ke produk aktif di DB lokal.
  final List<ParsedOrderItem> items;

  /// productUnitId (atau fragmen mentah) yang tidak ditemukan/sudah
  /// dinonaktifkan — ditampilkan sebagai peringatan, tidak menggagalkan
  /// baris lain yang valid.
  final List<String> notFound;

  final String? customerName;
  final String? customerPhone;
  final String? note;

  /// false bila teks yang ditempel sama sekali tidak mengandung kode mesin
  /// (`#PSN:...`) — dipakai UI untuk pesan error yang jelas, beda dari
  /// "ditemukan tapi semua item invalid".
  final bool hasMachineCode;

  int get total => items.fold(0, (s, i) => s + i.subtotal);
}
