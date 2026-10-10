import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/catalog_sticker_service.dart';
import '../../core/services/kasir_sticker_service.dart';
import '../../core/theme/app_overlays.dart';
import '../../core/widgets/app_sticker.dart';
import '../kasir/kasir_screen.dart'
    show kasirLandingTextProvider, kasirStickerProvider;

/// Slot mana yang memakai unggahan sendiri (bukan bawaan).
final _kasirStickerCustomProvider =
    FutureProvider.autoDispose<Map<KasirStickerSlot, bool>>((ref) async {
  final db = ref.watch(databaseProvider);
  return {
    for (final s in KasirStickerSlot.values)
      s: await KasirStickerService.isCustom(db, s),
  };
});

/// Slot yang sedang memakai override LOKAL (sementara) di perangkat non-owner.
final _kasirStickerLocalProvider =
    FutureProvider.autoDispose<Map<KasirStickerSlot, bool>>((ref) async {
  final db = ref.watch(databaseProvider);
  return {
    for (final s in KasirStickerSlot.values)
      s: await KasirStickerService.isLocalOverride(db, s),
  };
});

/// Lembar pengaturan stiker animasi Kasir (.tgs): dua tempat — landing &
/// "produk tidak ditemukan". Bawaan aplikasi, bisa diganti unggahan sendiri.
class KasirStickerSheet extends ConsumerWidget {
  const KasirStickerSheet({super.key});

  static Future<void> show(BuildContext context) => showAppSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => const KasirStickerSheet(),
      );

  Future<void> _pick(
      BuildContext context, WidgetRef ref, KasirStickerSlot slot) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;
    final v = CatalogStickerService.validateTgs(bytes);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (v.json == null) {
      messenger.showAppSnackBar(SnackBar(
          content: Text(v.error ?? 'Stiker tidak valid'),
          backgroundColor: Theme.of(context).colorScheme.error));
      return;
    }
    final local = !ref.read(deviceProvider).isOwner;
    await KasirStickerService.setCustom(
        ref.read(databaseProvider), slot, bytes,
        local: local);
    ref.invalidate(_kasirStickerCustomProvider);
    ref.invalidate(_kasirStickerLocalProvider);
    ref.invalidate(kasirStickerProvider(slot));
    messenger.showAppSnackBar(SnackBar(
        content: Text(local
            ? 'Stiker "${slot.label}" diganti di perangkat ini (kembali '
                'mengikuti owner saat sinkron)'
            : 'Stiker "${slot.label}" diganti')));
  }

  Future<void> _reset(WidgetRef ref, KasirStickerSlot slot) async {
    await KasirStickerService.resetToDefault(ref.read(databaseProvider), slot,
        local: !ref.read(deviceProvider).isOwner);
    ref.invalidate(_kasirStickerCustomProvider);
    ref.invalidate(_kasirStickerLocalProvider);
    ref.invalidate(kasirStickerProvider(slot));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(_kasirStickerCustomProvider).valueOrNull ??
        const <KasirStickerSlot, bool>{};
    final localOv = ref.watch(_kasirStickerLocalProvider).valueOrNull ??
        const <KasirStickerSlot, bool>{};
    final isOwner = ref.watch(deviceProvider).isOwner;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Stiker & Teks Landing Kasir',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            for (final slot in KasirStickerSlot.values)
              _StickerRow(
                slot: slot,
                isOwner: isOwner,
                isLocal: localOv[slot] == true,
                // Owner: tombol "Bawaan" bila ada unggahan. Non-owner: tombol
                // "Ikuti owner" HANYA bila ada override lokal.
                isCustom: isOwner ? custom[slot] == true : localOv[slot] == true,
                onPick: () => _pick(context, ref, slot),
                onReset: () => _reset(ref, slot),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Ganti dengan berkas stiker animasi .tgs (format stiker '
                'Telegram, maks 200 KB). Berkas tidak valid ditolak.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            // Teks di bawah stiker: owner = setting toko (tersinkron); non-owner
            // boleh mengubah SEMENTARA di perangkatnya (kembali mengikuti
            // owner saat sinkron — owner adalah sumber kebenaran).
            if (!isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Di perangkat ini perubahan stiker & teks bersifat '
                  'SEMENTARA: saat sinkron dengan owner, keduanya kembali '
                  'mengikuti owner.',
                  key: const Key('landing-local-note'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            _LandingTextEditor(local: !isOwner),
          ],
        ),
      ),
    );
  }
}

class _StickerRow extends ConsumerWidget {
  const _StickerRow({
    required this.slot,
    required this.isOwner,
    required this.isLocal,
    required this.isCustom,
    required this.onPick,
    required this.onReset,
  });

  final KasirStickerSlot slot;
  final bool isOwner;

  /// Memakai override lokal sementara (non-owner).
  final bool isLocal;
  final bool isCustom;
  final VoidCallback onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final json = ref.watch(kasirStickerProvider(slot)).valueOrNull;
    return ListTile(
      key: ValueKey('kasir-sticker-${slot.name}'),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: json == null
            ? const Icon(Icons.emoji_emotions_outlined)
            : AppSticker(json: json, size: 48),
      ),
      title: Text(slot.label),
      subtitle: Text(isLocal
          ? 'Sementara di perangkat ini'
          : (isOwner ? (isCustom ? 'Unggahan sendiri' : 'Bawaan') : 'Mengikuti owner')),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (isCustom)
            TextButton(
              key: ValueKey('kasir-sticker-reset-${slot.name}'),
              onPressed: onReset,
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              child: Text(isOwner ? 'Bawaan' : 'Ikuti owner'),
            ),
          TextButton(
            key: ValueKey('kasir-sticker-pick-${slot.name}'),
            onPressed: onPick,
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Ganti'),
          ),
        ],
      ),
    );
  }
}

/// Editor teks di bawah stiker (judul + subjudul) - HANYA owner. Kosong =
/// teks bawaan. Disimpan sebagai setting toko yang ikut tersinkron.
class _LandingTextEditor extends ConsumerStatefulWidget {
  const _LandingTextEditor({this.local = false});

  /// true = perangkat non-owner: simpan sbg override LOKAL sementara.
  final bool local;

  @override
  ConsumerState<_LandingTextEditor> createState() => _LandingTextEditorState();
}

class _LandingTextEditorState extends ConsumerState<_LandingTextEditor> {
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    var t = (await db.getSetting(KasirLandingText.titleKey)) ?? '';
    var s = (await db.getSetting(KasirLandingText.subtitleKey)) ?? '';
    if (widget.local) {
      // Non-owner: tampilkan nilai yang berlaku (override lokal bila ada,
      // kalau tidak nilai dari host).
      final lt = (await db.getSetting(KasirLocalOverrides.titleKey)) ?? '';
      final ls = (await db.getSetting(KasirLocalOverrides.subtitleKey)) ?? '';
      if (lt.isNotEmpty) t = lt;
      if (ls.isNotEmpty) s = ls;
    }
    if (!mounted) return;
    _title.text = t;
    _subtitle.text = s;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  Future<void> _save({bool reset = false}) async {
    if (reset) {
      _title.clear();
      _subtitle.clear();
    }
    await KasirLandingText.save(ref.read(databaseProvider),
        title: _title.text, subtitle: _subtitle.text, local: widget.local);
    ref.invalidate(kasirLandingTextProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showAppSnackBar(SnackBar(
        content: Text(widget.local
            ? (reset
                ? 'Teks landing kembali mengikuti owner'
                : 'Teks landing diubah di perangkat ini (kembali mengikuti '
                    'owner saat sinkron)')
            : (reset
                ? 'Teks landing kembali ke bawaan'
                : 'Teks landing disimpan'))));
    if (reset && widget.local) _load(); // tampilkan nilai dari host lagi
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Teks di bawah stiker',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('landing-text-title'),
            controller: _title,
            maxLength: KasirLandingText.maxTitle,
            decoration: InputDecoration(
              labelText: 'Judul',
              hintText: KasirLandingText.defaults.title,
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const Key('landing-text-subtitle'),
            controller: _subtitle,
            maxLength: KasirLandingText.maxSubtitle,
            decoration: InputDecoration(
              labelText: 'Keterangan',
              hintText: KasirLandingText.defaults.subtitle,
              isDense: true,
            ),
          ),
          Text(
              widget.local
                  ? 'Hanya di perangkat ini; saat sinkron kembali mengikuti '
                      'owner. Kosongkan untuk mengikuti owner.'
                  : 'Tersinkron ke semua perangkat toko. Kosongkan untuk teks '
                      'bawaan.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                key: const Key('landing-text-reset'),
                onPressed: () => _save(reset: true),
                style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                child: Text(widget.local ? 'Ikuti owner' : 'Bawaan'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('landing-text-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
