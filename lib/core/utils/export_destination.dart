import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Setelah file backup (BPOP2/BPOT1/dst) selesai dibuat: tanya user mau
/// disimpan ke penyimpanan perangkat (lewat `FilePicker.saveFile`, alur
/// lama) ATAU langsung dibagikan lewat share sheet OS (WhatsApp/Google
/// Drive/email/dst) TANPA pernah nangkring di storage lokal dulu. Dipakai
/// oleh SEMUA jenis file backup (`backup_screen.dart` BPOP2, `alih_owner_
/// screen.dart` BPOT1) supaya opsinya konsisten.
///
/// Return `true` kalau file benar-benar tersimpan/dibagikan (utk caller yg
/// perlu tahu apakah lanjut catat "backup terakhir", dst), `false` kalau
/// user batal.
Future<bool> saveOrShareExport({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  String? shareText,
}) async {
  // Dialog pilihan SENGAJA ditaruh di `content` (bukan `actions`) — 2 tombol
  // besar bersaing lebar dalam `Row` `actions` AlertDialog terbukti overflow
  // di HP sempit (gotcha dicatat di CLAUDE.md). Ditumpuk vertikal di content
  // sebagai gantinya (tiap tombol sendiri di barisnya, aman lebar penuh).
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Simpan Backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Simpan ke penyimpanan HP, atau bagikan langsung (mis. ke '
            'Google Drive/WhatsApp/email) tanpa disimpan lokal dulu.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'share'),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Bagikan'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'save'),
            icon: const Icon(Icons.save_alt_outlined),
            label: const Text('Simpan ke Perangkat'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Batal'),
        ),
      ],
    ),
  );
  if (choice == null) return false;

  if (choice == 'save') {
    final path = await FilePicker.platform
        .saveFile(fileName: fileName, bytes: bytes, type: FileType.any);
    return path != null;
  }

  // 'share' — tulis ke temp dir dulu (share_plus butuh path file sungguhan),
  // dibersihkan otomatis oleh TempShareCleanup (prefix 'backup_') spt file
  // share sementara lain (struk/katalog).
  final dir = await getTemporaryDirectory();
  final file = File(
      '${dir.path}/backup_${DateTime.now().millisecondsSinceEpoch}_$fileName');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path)], text: shareText);
  return true;
}
