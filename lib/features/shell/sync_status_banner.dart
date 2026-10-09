import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/sync_state_provider.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_notice_card.dart';

/// Item 21 (Fase 1) — banner status sync, tampil di tab MANAPUN selama ADA
/// yang layak dipantau (antrian menunggu, usulan menunggu, klien sedang
/// proses, ATAU konfirmasi sekali-tampil habis approve/tolak/reset) —
/// sebelumnya status ini cuma terlihat selagi persis di layar Sync WiFi, dan
/// proses klien ikut "hilang dari pandangan" begitu owner/kasir pindah tab
/// (walau prosesnya sendiri tetap jalan di background). Tap → lompat ke
/// layar Sync.
///
/// Bentuk kartu notifikasi inline (bukan bar tipis permanen) — SENGAJA
/// TIDAK lagi tampil hanya krn `hostRunning` semata (lihat dok
/// `SyncState.hasOngoing`): host aktif tanpa antrian apa pun bukan sesuatu
/// yang perlu terus dinotifikasi di tab lain, laporan nyata user.
///
/// Follow-up posisi (laporan nyata user "belum inline"): widget ini DULU
/// dipasang sekali di `MainShell`, mengambang di ATAS setiap layar tab
/// (termasuk di atas toolbar/AppBar masing-masing) — dianggap tidak
/// "inline" dibanding notifikasi lain di app (mis. `InlineBanner` yg tampil
/// DI BAWAH header/toolbar tiap layar). Sekarang dipasang LANGSUNG di tiap
/// layar tab (Ringkasan/Kasir/Produk/Pelanggan/Laporan/Pengaturan), persis
/// di bawah AppBar/toolbar masing-masing — sejajar dgn `InlineBanner` yg
/// sudah ada di situ. `SyncScreen` (sub-halaman Pengaturan) SENGAJA tidak
/// dipasangi (statusnya sudah tampil penuh di badan layarnya sendiri).
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncStateProvider);
    if (!sync.hasActivity) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showOngoing = sync.hasOngoing;
    final showTransient = sync.transientMessage != null;
    // Strip antrian di belakang HANYA muncul kalau KEDUANYA aktif bersamaan
    // (mis. baru saja approve satu item, tapi device lain masih menunggu
    // giliran) — bukan tumpukan permanen, hilang lagi begitu konfirmasi
    // sekali-tampil di depannya habis waktu.
    final showStrip = showOngoing && showTransient;

    // TANPA SafeArea di sini — widget ini SEKARANG selalu dipasang DI BAWAH
    // AppBar/toolbar layarnya masing-masing (bukan lagi di ATAS segalanya di
    // MainShell), jadi area tidak-aman (status bar) sudah dikonsumsi duluan
    // oleh AppBar/toolbar. Pola padding (12,8,12,0) meniru persis
    // `InlineBanner` yang sudah ada supaya jarak dari header ke banner
    // konsisten dgn notifikasi inline lain di app.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
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
    );
  }

  String _ongoingLabel(SyncState sync) {
    // Tahap klien yg tersisa di sini HANYA connecting/sending (network
    // aktif) — `waitingApproval` TIDAK LAGI masuk `clientSyncing` (lihat dok
    // di `SyncState`), jadi tidak pernah sampai ke cabang ini lagi.
    if (sync.clientSyncing) {
      return switch (sync.clientPhase) {
        ClientSyncPhase.connecting => 'Sync: menyambung ke host…',
        ClientSyncPhase.sending => 'Sync: mengirim data…',
        _ => 'Sync berjalan…',
      };
    }
    final waitingCount = sync.queue.length +
        sync.proposals.length +
        sync.laciMejaProposals.length;
    return 'Host aktif · $waitingCount menunggu persetujuan';
  }
}

/// Kartu notifikasi tunggal — kartu gaya baru bersama ([AppNoticeCard]):
/// putih membulat, ikon bulat beraksen, masuk dgn geser-turun + pudar.
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
    final t = switch (tone) {
      SyncBannerTone.success => ToastTone.success,
      SyncBannerTone.sync => ToastTone.sync,
    };
    final ink = isDark ? const Color(0xFFECE7DD) : const Color(0xFF2A2824);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.dur(context, AppMotion.medium),
      curve: AppMotion.easeOutQuint,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - v) * -10), child: child),
      ),
      child: AppNoticeCard(
        tone: t,
        icon: icon,
        spinning: spinning,
        onTap: () => context.push('/pengaturan/sync'),
        trailing: Icon(Icons.chevron_right, size: 18, color: ink.withOpacity(0.45)),
        child: Text(
          label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
