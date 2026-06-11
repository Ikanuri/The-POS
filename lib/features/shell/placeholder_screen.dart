import 'package:flutter/material.dart';

/// Placeholder untuk screen yang dibangun di phase berikutnya.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.phase,
    this.description = '',
  });

  final String title;
  final IconData icon;
  final String phase;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: scheme.outlineVariant),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (description.isNotEmpty)
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              const SizedBox(height: 16),
              Chip(
                label: Text('Hadir di $phase'),
                backgroundColor: scheme.primary.withOpacity(0.1),
                labelStyle: TextStyle(color: scheme.primary, fontSize: 12),
                side: BorderSide.none,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
