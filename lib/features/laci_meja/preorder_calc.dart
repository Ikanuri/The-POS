// Implementasinya dipindah ke `core/utils/preorder_calc.dart` supaya
// `AppDatabase` (layer core) ikut memakai rumus jaminan sisa yang SAMA utk
// penanda inline "· Titip N" di struk — file ini dipertahankan sbg
// re-export agar import lama di dashboard/laporan/test tidak berubah.
export '../../core/utils/preorder_calc.dart';
