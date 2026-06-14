import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dinaikkan setiap kali produk disimpan/diedit agar _catalogDetailProvider
/// (FutureProvider.family) ikut di-invalidate. Price-tiers changes don't
/// trigger watchProducts() stream, so this counter fills the gap.
final productUpdateCountProvider = StateProvider<int>((ref) => 0);
