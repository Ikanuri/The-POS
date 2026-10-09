import '../../core/theme/app_style.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFD97757), Color(0xFFC96442)],
                    ),
                    boxShadow: AppStyle.accentShadow,
                  ),
                  child: const Icon(Icons.storefront_outlined,
                      size: 44, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Selamat datang di',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              Text(
                'The POS',
                textAlign: TextAlign.center,
                style: AppTheme.numStyle(context,
                    size: 40, weight: FontWeight.w700, color: scheme.primary),
              ),
              const SizedBox(height: 12),
              Text(
                'Aplikasi kasir offline-first untuk toko grosir.\n'
                'Pilih cara memulai:',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: () => context.go('/setup/baru'),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Setup Toko Baru'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/setup/gabung'),
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('Gabung Toko'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/setup/pulihkan'),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Pulihkan dari File'),
              ),
              const SizedBox(height: 24),
              Text(
                'Setup Toko Baru: untuk HP owner (pertama kali).\n'
                'Gabung Toko: scan QR dari HP owner.\n'
                'Pulihkan dari File: sudah punya file backup/alihan owner.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
