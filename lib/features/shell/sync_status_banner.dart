import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/sync_state_provider.dart';
import '../../core/theme/app_theme.dart';

/// Item 21 (Fase 1) — banner status sync di level shell, tampil di tab/
/// halaman MANAPUN selama ADA yang layak dipantau (antrian menunggu, usulan
/// menunggu, klien sedang proses, ATAU konfirmasi sekali-tampil habis
/// approve/tolak/reset) — sebelumnya status ini cuma terlihat selagi persis
/// di layar Sync WiFi, dan proses klien ikut "hilang dari pandangan" begitu
/// owner/kasir pindah tab (walau prosesnya sendiri tetap jalan di
/// background). Tap → lompat ke layar Sync.
///
/// Bentuk kartu notifikasi inline (bukan bar tipis permanen) — SENGAJA
/// TIDAK lagi tampil hanya krn `hostRunning` semata (lihat dok
/// `SyncState.hasOngoing`): host aktif tanpa antrian apa pun bukan sesuatu
/// yang perlu terus dinotifikasi di tab lain, laporan nyata user.
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
    final showOngoing = sync.hasOngoing;
    final showTransient = sync.transientMessage != null;
    // Strip antrian di belakang HANYA muncul kalau KEDUANYA aktif bersamaan
    // (mis. baru saja approve satu item, tapi device lain masih menunggu
    // giliran) — bukan tumpukan permanen, hilang lagi begitu konfirmasi
    // sekali-tampil di depannya habis waktu.
    final showStrip = showOngoing && showTransient;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showStrip)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  key: const Key('sync_ongoing_strip'),
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.riwayatFg(isDark).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            if (showTransient)
              _SyncNotifCard(
                tone: sync.transientTone,
                isDark: isDark,
                icon: sync.transientTone == SyncBannerTone.success
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
                label: sync.transientMessage!,
              )
            else
              _SyncNotifCard(
                tone: SyncBannerTone.sync,
                isDark: isDark,
                icon: Icons.wifi_tethering_outlined,
                label: _ongoingLabel(sync),
                spinning: sync.clientSyncing,
              ),
          ],
        ),
      ),
    );
  }

  String _ongoingLabel(SyncState sync) {
    if (sync.clientSyncing) {
      return switch (sync.clientPhase) {
        ClientSyncPhase.connecting => 'Sync: menyambung ke host…',
        ClientSyncPhase.sending => 'Sync: mengirim data…',
        ClientSyncPhase.waitingApproval =>
          'Sync: menunggu persetujuan owner…',
        _ => 'Sync berjalan…',
      };
    }
    final waitingCount = sync.queue.length + sync.proposals.length;
    return 'Host aktif · $waitingCount menunggu persetujuan';
  }
}

/// Kartu notifikasi tunggal — gaya sama dgn `InlineBanner` (kartu bulat,
/// accent bar kiri, ikon, elevation) supaya konsisten dgn notifikasi inline
/// lain di app (mis. banner stok menipis di Kasir), bukan bar status
/// terpisah gayanya sendiri.
class _SyncNotifCard extends StatelessWidget {
  const _SyncNotifCard({
    required this.tone,
    required this.isDark,
    required this.icon,
    required this.label,
    this.spinning = false,
  });

  final SyncBannerTone tone;
  final bool isDark;
  final IconData icon;
  final String label;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tone) {
      SyncBannerTone.success => (
          AppTheme.changeBg(isDark),
          AppTheme.changeFg(isDark),
        ),
      SyncBannerTone.sync => (
          AppTheme.riwayatBg(isDark),
          AppTheme.riwayatFg(isDark),
        ),
    };

    return Material(
      elevation: 3,
      shadowColor: fg.withOpacity(0.25),
      borderRadius: BorderRadius.circular(12),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/pengaturan/sync'),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 3,
                height: 20,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: fg,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (spinning)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                Icon(icon, size: 18, color: fg),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: fg.withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
