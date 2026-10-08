import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/catalog_sticker_service.dart';
import '../../core/services/kasir_sticker_service.dart';
import '../../core/theme/app_overlays.dart';
import '../../core/widgets/app_sticker.dart';
import '../kasir/kasir_screen.dart' show kasirStickerProvider;

/// Slot mana yang memakai unggahan sendiri (bukan bawaan).
final _kasirStickerCustomProvider =
    FutureProvider.autoDispose<Map<KasirStickerSlot, bool>>((ref) async {
  final db = ref.watch(databaseProvider);
  return {
    for (final s in KasirStickerSlot.values)
      s: await KasirStickerService.isCustom(db, s),
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
    await KasirStickerService.setCustom(
        ref.read(databaseProvider), slot, bytes);
    ref.invalidate(_kasirStickerCustomProvider);
    ref.invalidate(kasirStickerProvider(slot));
    messenger.showAppSnackBar(
        SnackBar(content: Text('Stiker "${slot.label}" diganti')));
  }

  Future<void> _reset(WidgetRef ref, KasirStickerSlot slot) async {
    await KasirStickerService.resetToDefault(ref.read(databaseProvider), slot);
    ref.invalidate(_kasirStickerCustomProvider);
    ref.invalidate(kasirStickerProvider(slot));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(_kasirStickerCustomProvider).valueOrNull ??
        const <KasirStickerSlot, bool>{};
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
              child: Text('Stiker Animasi Kasir',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            for (final slot in KasirStickerSlot.values)
              _StickerRow(
                slot: slot,
                isCustom: custom[slot] == true,
                onPick: () => _pick(context, ref, slot),
                onReset: () => _reset(ref, slot),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Ganti dengan berkas stiker animasi .tgs (format stiker '
                'Telegram, maks 64 KB). Berkas tidak valid ditolak.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerRow extends ConsumerWidget {
  const _StickerRow({
    required this.slot,
    required this.isCustom,
    required this.onPick,
    required this.onReset,
  });

  final KasirStickerSlot slot;
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
      subtitle: Text(isCustom ? 'Unggahan sendiri' : 'Bawaan'),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (isCustom)
            TextButton(
              key: ValueKey('kasir-sticker-reset-${slot.name}'),
              onPressed: onReset,
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Bawaan'),
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
