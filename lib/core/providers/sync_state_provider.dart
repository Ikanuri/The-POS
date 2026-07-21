import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/lan_sync_service.dart';
import 'device_provider.dart';

/// Item 21 (Fase 1) — status progres sync sisi KLIEN. "Realtime per-baris"
/// SENGAJA tidak ada (protokol kirim semua tabel dalam satu request HTTP,
/// bukan streaming) — cukup tahapan kasar Menyambung→Mengirim→Menunggu.
enum ClientSyncPhase { idle, connecting, sending, waitingApproval, done, error }

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

  bool get clientSyncing =>
      clientPhase == ClientSyncPhase.connecting ||
      clientPhase == ClientSyncPhase.sending ||
      clientPhase == ClientSyncPhase.waitingApproval;

  /// true bila ADA proses/status yang layak ditampilkan sbg banner
  /// persisten di shell (host aktif, antrian menunggu, atau klien sedang
  /// jalan) — dipakai `main_shell.dart` memutuskan tampil/tidaknya banner.
  bool get hasActivity =>
      hostRunning || queue.isNotEmpty || proposals.isNotEmpty || clientSyncing;

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
    // Item 17 Fase 2 — antrian sekarang di DB (async), tidak bisa dibaca
    // langsung di initializer `super(...)` di atas spt versi lama (`List`
    // in-memory sinkron) — muat begitu notifier ini hidup. Bisa saja host
    // sudah aktif & py antrian SEBELUM provider ini dibangun (mis. widget
    // baru pertama kali baca provider setelah host sempat jalan lebih
    // dulu), jadi tetap perlu di-refresh di sini, bukan cuma andalkan
    // callback yang hanya menangkap perubahan SETELAHNYA.
    unawaited(_refreshQueue());
  }

  final Ref _ref;

  Future<void> _refreshQueue() async {
    if (!LanSyncService.isHostRunning) {
      state = state.copyWith(queue: const []);
      return;
    }
    final queue = await LanSyncService.loadPendingQueue();
    state = state.copyWith(queue: queue);
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
      state = state.copyWith(
        hostRunning: false,
        hostIp: '',
        hostToken: '',
        queue: const [],
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
    return received;
  }

  /// Item 17 Fase 2 — PERMANEN (lihat dok `LanSyncService.rejectSync`). UI
  /// pemanggil WAJIB sudah minta konfirmasi eksplisit sebelum ini.
  Future<void> rejectSync(String itemId) async {
    await LanSyncService.rejectSync(itemId);
    await _refreshQueue();
  }

  /// "Sync Ulang Penuh" — reset watermark upload klien ke epoch, escape
  /// hatch manual utk pemulihan kalau owner salah tolak atau curiga ada
  /// data yang belum pernah sampai ke host.
  Future<void> resetUploadWatermark() =>
      LanSyncService.resetUploadWatermark(_ref.read(databaseProvider));

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
    LanSyncService.onQueueChanged = null;
    LanSyncService.onProposalsChanged = null;
    super.dispose();
  }
}

final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  return SyncStateNotifier(ref);
});
