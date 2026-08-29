import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_id_service.dart';
import '../services/license_service.dart';

/// Item 25c — state gerbang lisensi. Disimpan di SharedPreferences (BUKAN
/// tabel settings di DB terenkripsi) karena gerbang ini harus bisa dicek
/// SEBELUM device setup selesai (sebelum storeKey ada, sebelum DB bisa
/// dibuka) — persis alasan yang sama kenapa `device_provider.dart` juga
/// pakai SharedPreferences utk identitas pra-DB.
class LicenseState {
  const LicenseState({
    this.fingerprint = '',
    this.exp,
    this.lastSeen,
    this.revoked = false,
    this.activatedAt,
    this.clockManipulated = false,
    this.deviceMismatch = false,
  });

  final String fingerprint;
  final String? exp; // null = belum pernah aktivasi.
  final DateTime? lastSeen;
  final bool revoked;
  // Item 25c/susulan — kapan device INI PERTAMA KALI aktivasi (ditampilkan
  // di halaman info lisensi). Tidak berubah saat renewal/reaktivasi berikutnya
  // — beda dari lastSeen yang terus maju tiap app dibuka.
  final DateTime? activatedAt;

  /// Susulan — jam sistem device terdeteksi jauh di BELAKANG jam server
  /// sungguhan (dicek opportunistic lewat header `Date` respons
  /// `revoked.json`, lihat dok [LicenseNotifier._fetchLiveStatus]). Menutup
  /// celah "set jam mundur SEKALI saat aktivasi lalu biarkan jalan normal" —
  /// `isClockRewound` cuma mendeteksi jam MUNDUR RELATIF ke riwayat device
  /// sendiri, tidak berdaya kalau device baru/`lastSeen` belum ada acuan.
  final bool clockManipulated;

  /// Susulan — data aplikasi (termasuk status lisensi) terindikasi
  /// DIPINDAHKAN ke device fisik lain (mis. tools "Pindah Data"/clone
  /// bawaan pabrikan OEM), dicek lokal lewat `ANDROID_ID` (lihat dok
  /// [LicenseNotifier._checkDeviceBinding]) — beda dari fingerprint acak
  /// yang MEMANG ikut ter-copy krn cuma tersimpan di SharedPreferences.
  final bool deviceMismatch;

  bool get isActivated => exp != null;

  bool get isClockRewound =>
      lastSeen != null && DateTime.now().isBefore(lastSeen!);

  bool get isExpired {
    if (exp == null || exp == 'selamanya') return false;
    final d = DateTime.tryParse(exp!);
    if (d == null) return true;
    return !DateTime.now().isBefore(d);
  }

  /// Gerbang lisensi BELUM dikonfigurasi (public key developer belum
  /// ditanam) → jangan pernah mengunci siapa pun.
  bool get isLocked {
    if (!LicenseService.isConfigured) return false;
    if (!isActivated) return true;
    if (revoked) return true;
    if (isClockRewound) return true;
    if (isExpired) return true;
    if (clockManipulated) return true;
    if (deviceMismatch) return true;
    return false;
  }

  /// Sisa hari sebelum habis — utk banner peringatan H-7. Null kalau tidak
  /// relevan (belum aktivasi/"selamanya"/sudah terkunci).
  int? get daysUntilExpiry {
    if (exp == null || exp == 'selamanya') return null;
    final d = DateTime.tryParse(exp!);
    if (d == null) return null;
    return d.difference(DateTime.now()).inDays;
  }

  /// Item 14 — label sisa waktu lisensi utk ditampilkan di Pengaturan, unit
  /// menyesuaikan sisa waktu (hari → jam → menit, satuan terkecil menit).
  /// Null kalau belum aktivasi atau lisensi "selamanya" (tidak relevan
  /// ditampilkan sbg countdown).
  String? get remainingLabel {
    if (exp == null || exp == 'selamanya') return null;
    final d = DateTime.tryParse(exp!);
    if (d == null) return null;
    final remaining = d.difference(DateTime.now());
    if (remaining.isNegative) return 'Kadaluarsa';
    if (remaining.inDays >= 1) return '${remaining.inDays} hari lagi';
    if (remaining.inHours >= 1) return '${remaining.inHours} jam lagi';
    return '${remaining.inMinutes} menit lagi';
  }

  /// Status lisensi utk ditampilkan — "Selamanya", countdown, "Kadaluarsa",
  /// atau null kalau belum aktivasi sama sekali.
  String? get licenseStatusLabel {
    if (!isActivated) return null;
    if (exp == 'selamanya') return 'Selamanya';
    return remainingLabel;
  }

  LicenseState copyWith({
    String? fingerprint,
    String? exp,
    DateTime? lastSeen,
    bool? revoked,
    DateTime? activatedAt,
    bool? clockManipulated,
    bool? deviceMismatch,
  }) =>
      LicenseState(
        fingerprint: fingerprint ?? this.fingerprint,
        exp: exp ?? this.exp,
        lastSeen: lastSeen ?? this.lastSeen,
        revoked: revoked ?? this.revoked,
        activatedAt: activatedAt ?? this.activatedAt,
        clockManipulated: clockManipulated ?? this.clockManipulated,
        deviceMismatch: deviceMismatch ?? this.deviceMismatch,
      );
}

class LicenseNotifier extends StateNotifier<LicenseState> {
  LicenseNotifier() : super(const LicenseState());

  static const _kFingerprint = 'license_fingerprint';
  static const _kExp = 'license_exp';
  static const _kLastSeen = 'license_last_seen';
  static const _kRevoked = 'license_revoked_cached';
  static const _kActivatedAt = 'license_activated_at';
  static const _kClockManipulated = 'license_clock_manipulated_cached';
  static const _kAndroidId = 'license_android_id';

  /// Daftar sidik jari yang dicabut (Lapis 3) — file JSON publik di GitHub
  /// Gist TERPISAH dari repo app (bukan `raw.githubusercontent.com/.../The-POS/...`
  /// lagi sejak repo utama direncanakan private permanen — raw fetch tanpa
  /// auth 404 di repo private, lihat docs/HANDOFF.md). Gist punya visibility
  /// sendiri, independen dari status private/public repo kode, jadi
  /// kill-switch ini tetap hidup terus apa pun status repo. WAJIB pakai URL
  /// raw TANPA hash revisi (`.../raw/<file>`, bukan `.../raw/<commit_sha>/<file>`)
  /// — versi berhash mengunci ke snapshot lama selamanya, edit gist berikutnya
  /// tidak akan pernah terlihat app. Dicek opportunistic (timeout pendek,
  /// gagal-diam kalau offline) — TIDAK PERNAH menahan startup atau
  /// memblokir fungsi inti.
  static const _revokedListUrl =
      'https://gist.githubusercontent.com/Ikanuri/ff6a99c3b1e642c81809b0664c8d681a/raw/revoked.json';

  /// Logika murni keputusan revoked dari isi `revoked.json` — diekstrak
  /// dari `_checkRevocation()` supaya testable tanpa mock jaringan.
  /// `lockAll` = sakelar darurat (Lapis 3 susulan): true → SEMUA device
  /// revoked terlepas dari fingerprint-nya ada di `dicabut` atau tidak,
  /// dipakai utk insiden skala besar yang tidak realistis ditangani
  /// satu-satu lewat daftar fingerprint (mis. private key generator bocor).
  static bool computeRevoked({
    required bool lockAll,
    required List<String> dicabut,
    required String fingerprint,
  }) =>
      lockAll ||
      dicabut.any((fp) => fp.toLowerCase() == fingerprint.toLowerCase());

  /// Logika murni keputusan blokir re-aktivasi — diekstrak supaya testable
  /// tanpa mock jaringan/kripto. [liveRevoked] = hasil [_fetchLiveStatus]
  /// (null kalau fetch gagal). [cachedRevoked] = status revoked yang SUDAH
  /// tersimpan sebelum percobaan aktivasi ini. Fail-safe: fetch gagal →
  /// pertahankan status cache (JANGAN asumsikan tidak revoked).
  static bool shouldBlockReactivation({
    required bool? liveRevoked,
    required bool cachedRevoked,
  }) =>
      liveRevoked ?? cachedRevoked;

  /// Susulan — deteksi device yang jamnya sengaja dimundurkan SEKALI (mis.
  /// diset manual ke tahun lampau lalu dibiarkan jalan normal dari titik
  /// itu) supaya `exp` (tanggal absolut) butuh bertahun-tahun utk "dikejar".
  /// `isClockRewound` tidak berdaya di sini krn cuma bandingkan MUNDUR
  /// RELATIF ke `lastSeen` milik device sendiri — kalau jam sudah salah
  /// SEJAK SEBELUM aktivasi pertama, tidak ada riwayat pembanding sama
  /// sekali. Cross-check ke header `Date` respons HTTP (jam server
  /// SUNGGUHAN, bukan input device) menutup celah itu.
  ///
  /// Murni parsing+bandingkan (diekstrak supaya testable tanpa mock
  /// jaringan) — [dateHeaderValue] header mentah, null/gagal parse →
  /// null (fail-open, BUKAN false — jangan pernah mengunci krn
  /// ketidaktahuan/header hilang). Toleransi 24 jam: device yang SEDIKIT
  /// meleset (belum sempat NTP sync, dll) tidak boleh ikut kena.
  static bool? computeClockManipulated({
    required String? dateHeaderValue,
    required DateTime deviceTimeUtc,
    Duration tolerance = const Duration(hours: 24),
  }) {
    if (dateHeaderValue == null) return null;
    final DateTime serverTimeUtc;
    try {
      serverTimeUtc = HttpDate.parse(dateHeaderValue);
    } catch (_) {
      return null;
    }
    return serverTimeUtc.difference(deviceTimeUtc) > tolerance;
  }

  /// Susulan — keputusan murni binding device fisik: [currentAndroidId]
  /// dibandingkan ke [storedAndroidId] (direkam saat pertama kali dilihat,
  /// lihat [_checkDeviceBinding]). Null/kosong di kedua sisi → tidak bisa
  /// disimpulkan, fail-open (false) — caller yang menangani "belum ada
  /// baseline, rekam sbg acuan baru" secara terpisah (bukan di sini, supaya
  /// fungsi ini tetap murni tanpa efek samping penulisan).
  static bool computeDeviceMismatch({
    required String? storedAndroidId,
    required String? currentAndroidId,
  }) {
    if (currentAndroidId == null || currentAndroidId.isEmpty) return false;
    if (storedAndroidId == null || storedAndroidId.isEmpty) return false;
    return currentAndroidId != storedAndroidId;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    var fingerprint = prefs.getString(_kFingerprint);
    if (fingerprint == null) {
      fingerprint = LicenseService.generateFingerprint();
      await prefs.setString(_kFingerprint, fingerprint);
    }

    final lastSeenRaw = prefs.getString(_kLastSeen);
    final activatedAtRaw = prefs.getString(_kActivatedAt);
    final deviceMismatch = await _checkDeviceBinding(prefs);

    state = LicenseState(
      fingerprint: fingerprint,
      exp: prefs.getString(_kExp),
      lastSeen: lastSeenRaw == null ? null : DateTime.tryParse(lastSeenRaw),
      revoked: prefs.getBool(_kRevoked) ?? false,
      activatedAt:
          activatedAtRaw == null ? null : DateTime.tryParse(activatedAtRaw),
      clockManipulated: prefs.getBool(_kClockManipulated) ?? false,
      deviceMismatch: deviceMismatch,
    );

    // Ratchet: majukan "waktu terakhir terlihat" tiap app dibuka wajar
    // (bukan setelah jam dimundurkan) — independen dari status kadaluarsa.
    if (state.isActivated && !state.isClockRewound) {
      await _touchLastSeen(prefs);
    }

    unawaited(_checkRevocation());
  }

  /// Susulan — binding ANDROID_ID: rekam identitas device FISIK saat
  /// pertama kali terlihat (baik fresh install MAUPUN update dari versi
  /// app sebelum fitur ini ada — device yang SEDANG JALAN saat itu dianggap
  /// baseline yang sah, BUKAN mismatch, krn belum ada apa pun utk
  /// dibandingkan). Baru terdeteksi mismatch kalau SUDAH ada baseline
  /// tersimpan DAN device sekarang beda dari itu — indikasi data aplikasi
  /// (SharedPreferences) dipindahkan ke device lain (mis. tools "Pindah
  /// Data"/clone bawaan pabrikan), bukan aktivasi baru yang wajar (aktivasi
  /// baru MEMANG selalu fingerprint acak baru, tidak menyentuh baseline ini
  /// sama sekali).
  ///
  /// Gagal ambil ANDROID_ID (bukan Android/error platform channel) →
  /// fail-open (false), TIDAK PERNAH mengunci krn ketidaktahuan.
  Future<bool> _checkDeviceBinding(SharedPreferences prefs) async {
    final current = await DeviceIdService.getAndroidId();
    if (current == null || current.isEmpty) return false;
    final stored = prefs.getString(_kAndroidId);
    if (stored == null || stored.isEmpty) {
      await prefs.setString(_kAndroidId, current);
      return false;
    }
    return computeDeviceMismatch(
        storedAndroidId: stored, currentAndroidId: current);
  }

  Future<void> _touchLastSeen(SharedPreferences prefs) async {
    final now = DateTime.now();
    await prefs.setString(_kLastSeen, now.toIso8601String());
    state = state.copyWith(lastSeen: now);
  }

  /// Aktivasi/reaktivasi. **Susulan (bug ditemukan user)**: sebelumnya
  /// method ini unconditionally set `revoked=false` begitu tanda tangan
  /// kode valid — device yang SUDAH di-revoke bisa "membuka diri sendiri"
  /// cuma dgn memasukkan ulang kode yang SAMA (revoked terpisah dari kode,
  /// terikat ke fingerprint via `revoked.json`; kode ber-`exp:'selamanya'`
  /// yang belum kadaluarsa tetap valid tanda tangannya selamanya). Sekarang
  /// cek status revoked LIVE dulu sebelum membuka gerbang — kalau
  /// fingerprint MASIH ada di `revoked.json` saat itu, aktivasi ditolak
  /// walau tanda tangan kodenya valid. Gagal fetch (offline) → fallback ke
  /// status revoked yang SUDAH ter-cache (fail-safe utk re-aktivasi —
  /// beda dari `_checkRevocation()` rutin yang sengaja fail-open, di sini
  /// kita tidak boleh diam-diam membuka device yang sedang dicurigai
  /// revoked hanya karena jaringan kebetulan mati).
  ///
  /// **Susulan ke-2 (bug produksi ditemukan user, real device)**: binding
  /// `ANDROID_ID` (`_checkDeviceBinding`, dicek di `load()`) TIDAK pernah
  /// direset di sini sebelumnya — begitu `deviceMismatch` sekali ter-set
  /// true (mis. ANDROID_ID device berubah krn update OS/factory reset
  /// resmi, BUKAN cuma skenario clone), reaktivasi dgn kode VALID sekalipun
  /// tidak membuka gerbang lagi (baseline lama tetap beda dari device
  /// sekarang selamanya) — pelanggan JUJUR bisa terkunci PERMANEN tanpa
  /// jalan keluar dari dalam app. Fix: aktivasi BERHASIL sekarang jadi
  /// titik "percaya ulang" — baseline ANDROID_ID direkam ULANG ke device
  /// yang SEDANG dipakai (tanpa syarat, menimpa baseline lama), status
  /// `deviceMismatch` ikut dibersihkan. Trade-off yang disadari: device
  /// hasil clone BISA membuka diri lagi kalau pemegangnya JUGA punya kode
  /// yang masih valid (belum revoked/expired) — beda kelas ancaman dari
  /// "clone diam-diam tanpa jejak apa pun" yang jadi concern awal fitur
  /// ini; reaktivasi tetap butuh langkah aktif & kode sah, tetap ada sinyal.
  Future<LicenseVerifyResult> activate(String code) async {
    final result = await LicenseService.verify(
      code,
      publicKeyB64: LicenseService.publicKeyBase64,
      deviceFingerprint: state.fingerprint,
    );
    if (!result.isOk) return result;

    final live = await _fetchLiveStatus(state.fingerprint);
    if (shouldBlockReactivation(
        liveRevoked: live.revoked, cachedRevoked: state.revoked)) {
      return const LicenseVerifyResult.fail('revoked');
    }

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_kExp, result.payload!.exp);
    await prefs.setString(_kLastSeen, now.toIso8601String());
    await prefs.setBool(_kRevoked, false);
    // Hanya dicatat sekali (aktivasi PERTAMA) — renewal/reaktivasi berikutnya
    // tidak menimpa tanggal ini, supaya "tanggal diaktifkan" tetap bermakna
    // histori device, bukan histori kode terbaru.
    var activatedAt = state.activatedAt;
    if (activatedAt == null) {
      activatedAt = now;
      await prefs.setString(_kActivatedAt, now.toIso8601String());
    }

    final deviceMismatch = await rebindDeviceId(prefs);

    state = state.copyWith(
      exp: result.payload!.exp,
      lastSeen: now,
      revoked: false,
      activatedAt: activatedAt,
      deviceMismatch: deviceMismatch,
    );
    return result;
  }

  /// Rebind baseline ANDROID_ID ke device yang SEDANG dipakai (dipanggil
  /// dari [activate] saat reaktivasi berhasil — lihat dok di sana). Public
  /// (`@visibleForTesting`) & diekstrak terpisah dari [activate] supaya
  /// testable TANPA perlu kode aktivasi valid sungguhan (private key
  /// produksi tidak pernah ada di repo, jadi `activate()` end-to-end tidak
  /// bisa ditest langsung). Return: `deviceMismatch` BARU yang seharusnya
  /// dipakai (false kalau rebind berhasil; nilai LAMA `state.deviceMismatch`
  /// apa adanya kalau gagal baca ANDROID_ID — fail-open, konsisten dgn
  /// `_checkDeviceBinding`).
  @visibleForTesting
  Future<bool> rebindDeviceId(SharedPreferences prefs) async {
    final current = await DeviceIdService.getAndroidId();
    if (current == null || current.isEmpty) return state.deviceMismatch;
    await prefs.setString(_kAndroidId, current);
    return false;
  }

  /// Ambil status revoked & indikasi manipulasi jam TERKINI dari SATU fetch
  /// yang sama ke `revoked.json` (header `Date` respons-nya dipakai sbg
  /// jam server tepercaya, lihat dok [computeClockManipulated] — tidak
  /// menambah request baru). Kedua field null kalau fetch gagal total
  /// (offline/timeout/format salah). Dipakai bareng oleh [_checkRevocation]
  /// (pengecekan rutin startup, fail-open) dan [activate] (re-aktivasi,
  /// fail-safe KHUSUS utk field `revoked` — lihat catatan di sana; field
  /// `clockManipulated` tidak dipakai di jalur aktivasi, cuma pengecekan
  /// rutin).
  Future<({bool? revoked, bool? clockManipulated})> _fetchLiveStatus(
      String fingerprint) async {
    if (!LicenseService.isConfigured || fingerprint.isEmpty) {
      return (revoked: null, clockManipulated: null);
    }
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client
          .getUrl(Uri.parse(_revokedListUrl))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return (revoked: null, clockManipulated: null);

      final clockManipulated = computeClockManipulated(
        dateHeaderValue: res.headers.value('date'),
        deviceTimeUtc: DateTime.now().toUtc(),
      );

      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final revoked = computeRevoked(
        lockAll: data['lockAll'] as bool? ?? false,
        dicabut: (data['dicabut'] as List?)?.cast<String>() ?? const [],
        fingerprint: fingerprint,
      );
      return (revoked: revoked, clockManipulated: clockManipulated);
    } catch (_) {
      return (revoked: null, clockManipulated: null);
    } finally {
      client?.close();
    }
  }

  Future<void> _checkRevocation() async {
    final live = await _fetchLiveStatus(state.fingerprint);
    // Gagal-diam — offline/timeout, jangan pernah blokir fungsi inti.
    if (live.revoked == null && live.clockManipulated == null) return;

    final prefs = await SharedPreferences.getInstance();
    var nextState = state;
    var changed = false;

    if (live.revoked != null && live.revoked != state.revoked) {
      await prefs.setBool(_kRevoked, live.revoked!);
      nextState = nextState.copyWith(revoked: live.revoked!);
      changed = true;
    }
    if (live.clockManipulated != null &&
        live.clockManipulated != state.clockManipulated) {
      await prefs.setBool(_kClockManipulated, live.clockManipulated!);
      nextState = nextState.copyWith(clockManipulated: live.clockManipulated!);
      changed = true;
    }
    if (changed) state = nextState;
  }
}

final licenseProvider =
    StateNotifierProvider<LicenseNotifier, LicenseState>((ref) {
  return LicenseNotifier();
});
