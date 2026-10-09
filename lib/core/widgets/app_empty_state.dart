import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Status kosong gaya landing: lingkaran ikon lembut + satu kalimat (+ saran).
/// Pakai ini untuk semua "Belum ada…/Tidak ada…" di layar penuh/daftar.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState(this.message,
      {super.key, this.icon = Icons.inbox_outlined, this.hint, this.action});

  final String message;
  final IconData icon;
  final String? hint;

  /// Aksi utama opsional (mis. tombol Tambah).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = AppMotion.reduced(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduced ? 1 : 0, end: 1),
          duration: AppMotion.dur(context, AppMotion.medium),
          curve: AppMotion.easeOutQuint,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
                offset: Offset(0, (1 - t) * 8), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withOpacity(0.12),
                ),
                child: Icon(icon, size: 26, color: cs.primary),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
