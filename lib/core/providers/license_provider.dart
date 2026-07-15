import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final String fingerprint;
  final String? exp; // null = belum pernah aktivasi.
  final DateTime? lastSeen;
  final bool revoked;

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
}

class LicenseNotifier extends StateNotifier<LicenseState> {
  LicenseNotifier() : super(const LicenseState());

  static const _kFingerprint = 'license_fingerprint';
  static const _kExp = 'license_exp';
  static const _kLastSeen = 'license_last_seen';
  static const _kRevoked = 'license_revoked_cached';

  /// File JSON publik di repo app sendiri (Lapis 3) — daftar sidik jari yang
  /// dicabut. Dicek opportunistic (timeout pendek, gagal-diam kalau offline)
  /// — TIDAK PERNAH menahan startup atau memblokir fungsi inti.
  static const _revokedListUrl =
      'https://raw.githubusercontent.com/Ikanuri/The-POS/main/license/revoked.json';

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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    var fingerprint = prefs.getString(_kFingerprint);
    if (fingerprint == null) {
      fingerprint = LicenseService.generateFingerprint();
      await prefs.setString(_kFingerprint, fingerprint);
    }

    final lastSeenRaw = prefs.getString(_kLastSeen);
    state = LicenseState(
      fingerprint: fingerprint,
      exp: prefs.getString(_kExp),
      lastSeen: lastSeenRaw == null ? null : DateTime.tryParse(lastSeenRaw),
      revoked: prefs.getBool(_kRevoked) ?? false,
    );

    // Ratchet: majukan "waktu terakhir terlihat" tiap app dibuka wajar
    // (bukan setelah jam dimundurkan) — independen dari status kadaluarsa.
    if (state.isActivated && !state.isClockRewound) {
      await _touchLastSeen(prefs);
    }

    unawaited(_checkRevocation());
  }

  Future<void> _touchLastSeen(SharedPreferences prefs) async {
    final now = DateTime.now();
    await prefs.setString(_kLastSeen, now.toIso8601String());
    state = LicenseState(
      fingerprint: state.fingerprint,
      exp: state.exp,
      lastSeen: now,
      revoked: state.revoked,
    );
  }

  Future<LicenseVerifyResult> activate(String code) async {
    final result = await LicenseService.verify(
      code,
      publicKeyB64: LicenseService.publicKeyBase64,
      deviceFingerprint: state.fingerprint,
    );
    if (!result.isOk) return result;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_kExp, result.payload!.exp);
    await prefs.setString(_kLastSeen, now.toIso8601String());
    await prefs.setBool(_kRevoked, false);
    state = LicenseState(
      fingerprint: state.fingerprint,
      exp: result.payload!.exp,
      lastSeen: now,
      revoked: false,
    );
    return result;
  }

  Future<void> _checkRevocation() async {
    if (!LicenseService.isConfigured || state.fingerprint.isEmpty) return;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client
          .getUrl(Uri.parse(_revokedListUrl))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final revoked = computeRevoked(
        lockAll: data['lockAll'] as bool? ?? false,
        dicabut: (data['dicabut'] as List?)?.cast<String>() ?? const [],
        fingerprint: state.fingerprint,
      );
      if (revoked != state.revoked) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kRevoked, revoked);
        state = LicenseState(
          fingerprint: state.fingerprint,
          exp: state.exp,
          lastSeen: state.lastSeen,
          revoked: revoked,
        );
      }
    } catch (_) {
      // Gagal-diam — offline/timeout, jangan pernah blokir fungsi inti.
    } finally {
      client?.close();
    }
  }
}

final licenseProvider =
    StateNotifierProvider<LicenseNotifier, LicenseState>((ref) {
  return LicenseNotifier();
});
