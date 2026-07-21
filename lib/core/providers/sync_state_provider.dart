import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/lan_sync_service.dart';
import 'device_provider.dart';

/// Item 21 (Fase 1) — status progres sync sisi KLIEN. "Realtime per-baris"
/// SENGAJA tidak ada (protokol kirim semua tabel dalam satu request HTTP,
/// bukan streaming) — cukup tahapan kasar Menyambung→Mengirim→Menunggu.
enum ClientSyncPhase { idle, connecting, sending, waitingApproval, done, error }

/// Nuansa warna kartu notifikasi banner sync — `sync` (ungu, konsisten dgn
/// warna domain "Sinkronisasi" di seluruh app) dipakai utk status
/// berlangsung (antrian menunggu/klien sedang proses) MAUPUN konfirmasi
/// netral (ditolak, Sync Ulang Penuh); `success` (hijau) KHUSUS konfirmasi
/// approve berhasil.
enum SyncBannerTone { sync, success }

/// Snapshot state sync global — dulu tersebar sbg local `State` field di
/// `SyncScreen` (`_hostRunning`, `_queue`, `_syncing`, dst), sekarang satu
/// sumber kebenaran supaya bisa dibaca dari layar MANA PUN (banner
/// persisten di shell) & tidak hilang saat layar Sync ditinggalkan.
class SyncState {
  const SyncState({
    this.hostRunning = false,
    this.hostIp = '',
    this.hostToken = '',
    this.refreshingIp = false,
    this.queue = const [],
    this.proposals = const [],
    this.timeoutProfile = SyncTimeoutProfile.normal,
    this.clientPhase = ClientSyncPhase.idle,
    this.clientResultMessage,
    this.transientMessage,
    this.transientTone = SyncBannerTone.sync,
  });

  final bool hostRunning;
  final String hostIp;
  final String hostToken;
  final bool refreshingIp;
  final List<PendingSyncItem> queue;
  final List<PendingProductProposal> proposals;
  final SyncTimeoutProfile timeoutProfile;
  final ClientSyncPhase clientPhase;
  final String? clientResultMessage;

  /// Pesan konfirmasi SEKALI-TAMPIL (mis. "Disetujui — N baris diterima")
  /// yang otomatis hilang sendiri (lihat `SyncStateNotifier._showTransient`)
  /// — BUKAN status berlangsung. Dipakai banner shell supaya event
  /// approve/tolak/reset terasa "beres", bukan menetap selamanya.
  final String? transientMessage;
  final SyncBannerTone transientTone;

  bool get clientSyncing =>
      clientPhase == ClientSyncPhase.connecting ||
      clientPhase == ClientSyncPhase.sending ||
      clientPhase == ClientSyncPhase.waitingApproval;

  /// true bila ADA proses yang MASIH berlangsung & layak dipantau (antrian
  /// menunggu, usulan menunggu, atau klien sedang proses) — SENGAJA TIDAK
  /// termasuk `hostRunning` semata: host aktif tanpa antrian apa pun bukan
  /// sesuatu yang perlu dinotifikasi terus-menerus di tab lain (dulu bikin
  /// banner "Host aktif" menetap selamanya selama host hidup, walau tidak
  /// ada yang perlu ditinjau — laporan nyata user).
  bool get hasOngoing =>
      queue.isNotEmpty || proposals.isNotEmpty || clientSyncing;

  /// true bila ADA sesuatu yang layak ditampilkan sbg banner shell (ongoing
  /// ATAU konfirmasi sekali-tampil) — dipakai `main_shell.dart` memutuskan
  /// tampil/tidaknya banner.
  bool get hasActivity => hasOngoing || transientMessage != null;

  SyncState copyWith({
    bool? hostRunning,
    String? hostIp,
    String? hostToken,
    bool? refreshingIp,
    List<PendingSyncItem>? queue,
    List<PendingProductProposal>? proposals,
    SyncTimeoutProfile? timeoutProfile,
    ClientSyncPhase? clientPhase,
    Object? clientResultMessage = _sentinel,
    Object? transientMessage = _sentinel,
    SyncBannerTone? transientTone,
  }) {
    return SyncState(
      hostRunning: hostRunning ?? this.hostRunning,
      hostIp: hostIp ?? this.hostIp,
      hostToken: hostToken ?? this.hostToken,
      refreshingIp: refreshingIp ?? this.refreshingIp,
      queue: queue ?? this.queue,
      proposals: proposals ?? this.proposals,
      timeoutProfile: timeoutProfile ?? this.timeoutProfile,
      clientPhase: clientPhase ?? this.clientPhase,
      clientResultMessage: identical(clientResultMessage, _sentinel)
          ? this.clientResultMessage
          : clientResultMessage as String?,
      transientMessage: identical(transientMessage, _sentinel)
          ? this.transientMessage
          : transientMessage as String?,
      transientTone: transientTone ?? this.transientTone,
    );
  }
}

const _sentinel = Object();

/// Item 21 (Fase 1) — pemilik state sync global. TIDAK pernah memanggil
/// `stopHost()` di `dispose()` (beda dari `_SyncScreenState` lama) — host
/// sengaja BERTAHAN selama app hidup, independen dari navigasi
/// tab/halaman, sampai user EKSPLISIT tekan "Stop Server". Karena provider
/// ini hidup sepanjang sesi app (bukan `.autoDispose`), ini otomatis
/// menyelesaikan bug lama: `SyncScreen.dispose()` mematikan host total
/// begitu owner pindah tab.
///
/// Sekalian menutup celah P3 lama (PLAN.md Item 41 E): `LanSyncService.
/// onQueueChanged`/`onProposalsChanged` adalah field callback TUNGGAL
/// (bukan daftar listener) — dulu kalau lebih dari satu tempat mendaftar,
/// yang belakangan menimpa yang duluan. Sekarang HANYA notifier ini yang
/// pernah mendaftar ke keduanya, jadi tidak ada lagi risiko tabrakan.
class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier(this._ref)
      : super(SyncState(
          hostRunning: LanSyncService.isHostRunning,
          // Item 40 (usulan produk) TETAP in-memory (di luar scope Item 17
          // Fase 2 — hanya antrian data append-only yang dipersist).
          proposals: LanSyncService.pendingProposals.toList(),
        )) {
    LanSyncService.onQueueChanged = () {
      unawaited(_refreshQueue());
    };
    LanSyncService.onProposalsChanged = () {
      state =
          state.copyWith(proposals: LanSyncService.pendingProposals.toList());
    };
    // Pasang `_db` SEGERA (bukan menunggu owner tap "Mulai Sebagai Host") —
    // antrian `sync_upload_queue` adalah data DB persisten, independen dari
    // socket host sedang jalan atau tidak. Tanpa ini, antrian tampak
    // "hilang" di layar Sync setelah app di-force-stop/clear RAM sampai host
    // direstart manual, walau baris DB-nya sendiri selamat — bug nyata
    // dilaporkan user.
    LanSyncService.attachDb(_ref.read(databaseProvider));
    // Item 17 Fase 2 — antrian sekarang di DB (async), tidak bisa dibaca
    // langsung di initializer `super(...)` di atas spt versi lama (`List`
    // in-memory sinkron) — muat begitu notifier ini hidup.
    unawaited(_refreshQueue());
  }

  final Ref _ref;
  Timer? _transientTimer;
  bool _disposed = false;

  Future<void> _refreshQueue() async {
    final queue = await LanSyncService.loadPendingQueue();
    state = state.copyWith(queue: queue);
  }

  /// Tampilkan pesan konfirmasi sekali-tampil di banner shell, otomatis
  /// hilang sendiri setelah [duration] — dipakai event selesai (approve/
  /// tolak/reset), BUKAN status berlangsung (lihat dok `SyncState.
  /// transientMessage`). Timer lama dibatalkan dulu supaya event beruntun
  /// (mis. approve lalu langsung reset) tidak saling potong durasi tampil.
  void _showTransient(String message, SyncBannerTone tone,
      {Duration duration = const Duration(seconds: 4)}) {
    _transientTimer?.cancel();
    state = state.copyWith(transientMessage: message, transientTone: tone);
    _transientTimer = Timer(duration, () {
      if (_disposed) return;
      state = state.copyWith(transientMessage: null);
    });
  }

  Future<void> loadTimeoutProfile() async {
    final db = _ref.read(databaseProvider);
    final profile = await SyncTimeoutProfile.load(db);
    state = state.copyWith(timeoutProfile: profile);
  }

  Future<void> setTimeoutProfile(SyncTimeoutProfile profile) async {
    state = state.copyWith(timeoutProfile: profile);
    await SyncTimeoutProfile.save(_ref.read(databaseProvider), profile);
  }

  Future<void> refreshIp() async {
    state = state.copyWith(refreshingIp: true);
    try {
      final ip = await LanSyncService.refreshHostIp();
      state = state.copyWith(hostIp: ip, refreshingIp: false);
    } catch (_) {
      state = state.copyWith(refreshingIp: false);
      rethrow;
    }
  }

  Future<void> toggleHost() async {
    if (state.hostRunning) {
      await LanSyncService.stopHost();
      // Antrian TIDAK ikut dikosongkan — persisten di DB, independen dari
      // socket host sedang jalan atau tidak (lihat dok `attachDb`).
      state = state.copyWith(
        hostRunning: false,
        hostIp: '',
        hostToken: '',
      );
      return;
    }
    final device = _ref.read(deviceProvider);
    final db = _ref.read(databaseProvider);
    final (ip, token) =
        await LanSyncService.startHost(db: db, storeKey: device.storeKey!);
    state = state.copyWith(hostRunning: true, hostIp: ip, hostToken: token);
    await _refreshQueue();
  }

  Future<int> approveSync(String itemId, {Set<String>? allowedTables}) async {
    final received =
        await LanSyncService.approveSync(itemId, allowedTables: allowedTables);
    await _refreshQueue();
    _showTransient('Disetujui — $received baris diterima', SyncBannerTone.success);
    return received;
  }

  /// Item 17 Fase 2 — PERMANEN (lihat dok `LanSyncService.rejectSync`). UI
  /// pemanggil WAJIB sudah minta konfirmasi eksplisit sebelum ini.
  Future<void> rejectSync(String itemId) async {
    await LanSyncService.rejectSync(itemId);
    await _refreshQueue();
    _showTransient('Data sync ditolak', SyncBannerTone.sync);
  }

  /// "Sync Ulang Penuh" — reset watermark upload klien ke epoch, escape
  /// hatch manual utk pemulihan kalau owner salah tolak atau curiga ada
  /// data yang belum pernah sampai ke host.
  Future<void> resetUploadWatermark() async {
    await LanSyncService.resetUploadWatermark(_ref.read(databaseProvider));
    _showTransient('Sync Ulang Penuh diaktifkan', SyncBannerTone.sync);
  }

  Future<SyncResult> sync({
    required String ip,
    required String token,
  }) async {
    state = state.copyWith(
        clientPhase: ClientSyncPhase.connecting, clientResultMessage: null);
    try {
      final device = _ref.read(deviceProvider);
      final db = _ref.read(databaseProvider);
      // Item 21 — tahap "Mengirim" ditandai sesaat sebelum panggilan
      // network (protokol tidak streaming, jadi tidak ada titik tengah
      // sungguhan antara "menyambung" & "mengirim" — cukup kasar spt
      // sudah disepakati, jangan overpromise granularitas per-baris).
      state = state.copyWith(clientPhase: ClientSyncPhase.sending);
      final result = await LanSyncService.syncToHost(
        db: db,
        storeKey: device.storeKey!,
        hostIp: ip,
        syncToken: token,
        connectTimeout: state.timeoutProfile.connectTimeout,
        responseTimeout: state.timeoutProfile.responseTimeout,
      );
      state = state.copyWith(
        clientPhase: result.pendingApproval
            ? ClientSyncPhase.waitingApproval
            : ClientSyncPhase.done,
        clientResultMessage: result.pendingApproval
            ? 'Data terkirim, menunggu persetujuan owner di perangkat host.\n'
                'Diterima dari host: ${result.received} baris.'
            : 'Selesai! Diterima: ${result.received} baris, Dikirim: ${result.sent} baris',
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        clientPhase: ClientSyncPhase.error,
        clientResultMessage: 'Gagal: $e',
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _transientTimer?.cancel();
    LanSyncService.onQueueChanged = null;
    LanSyncService.onProposalsChanged = null;
    super.dispose();
  }
}

final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  return SyncStateNotifier(ref);
});
