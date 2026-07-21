import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/sync_state_provider.dart';
import '../../core/theme/app_theme.dart';

/// Item 21 (Fase 1) — banner status sync PERSISTEN di level shell, tampil
/// di tab/halaman MANAPUN selama ada aktivitas sync (host aktif, antrian
/// menunggu, atau klien sedang proses) — sebelumnya status ini cuma
/// terlihat selagi persis di layar Sync WiFi, dan proses klien ikut
/// "hilang dari pandangan" begitu owner/kasir pindah tab (walau prosesnya
/// sendiri tetap jalan di background). Tap → lompat ke layar Sync.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key, this.hideOnSyncScreen = false});

  /// true bila layar saat ini SUDAH layar Sync sendiri — banner redundan
  /// di situ (statusnya sudah tampil penuh di badan layar), jadi disembunyikan.
  final bool hideOnSyncScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncStateProvider);
    if (hideOnSyncScreen || !sync.hasActivity) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final waitingCount = sync.queue.length + sync.proposals.length;

    final String label;
    if (sync.clientSyncing) {
      label = switch (sync.clientPhase) {
        ClientSyncPhase.connecting => 'Sync: menyambung ke host…',
        ClientSyncPhase.sending => 'Sync: mengirim data…',
        ClientSyncPhase.waitingApproval =>
          'Sync: menunggu persetujuan owner…',
        _ => 'Sync berjalan…',
      };
    } else if (waitingCount > 0) {
      label = 'Host aktif · $waitingCount menunggu persetujuan';
    } else {
      label = 'Host aktif · menunggu perangkat lain sync';
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(10),
          color: AppTheme.riwayatBg(isDark),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.push('/pengaturan/sync'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  if (sync.clientSyncing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.riwayatFg(isDark),
                      ),
                    )
                  else
                    Icon(Icons.wifi_tethering_outlined,
                        size: 16, color: AppTheme.riwayatFg(isDark)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.riwayatFg(isDark),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppTheme.riwayatFg(isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
