import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/crash_log_service.dart';

/// Layar diagnostik: tampilkan isi file log crash lokal (lihat
/// `CrashLogService`) apa adanya + tombol bagikan. Murni bonus kenyamanan —
/// jaring pengaman UTAMA-nya adalah file itu sendiri, bisa dibaca lewat
/// File Manager walau app tidak sempat terbuka sama sekali (lihat
/// docs/HANDOFF.md untuk konteks lengkap diskusi diagnosis crash).
class CrashLogScreen extends StatefulWidget {
  const CrashLogScreen({super.key});

  @override
  State<CrashLogScreen> createState() => _CrashLogScreenState();
}

class _CrashLogScreenState extends State<CrashLogScreen> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await CrashLogService.readAll();
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  Future<void> _share() async {
    final content = await CrashLogService.readAll();
    if (content == null) return;
    await Share.share(content, subject: 'Log Error The POS');
  }

  Future<void> _clear() async {
    await CrashLogService.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Error Terakhir'),
        actions: [
          if (_content != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Bagikan',
              onPressed: _share,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _content == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Belum ada error yang tercatat.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _content!,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _clear,
                          child: const Text('Hapus Log'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
