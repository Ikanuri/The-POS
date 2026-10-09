# Data dummy backup — Toko Berkah Jaya (DEMO)

Dibuat otomatis oleh `test/dummy_backup_generator_test.dart` (`DUMMY_BACKUP_OUT=docs/test-data flutter test test/dummy_backup_generator_test.dart`).

- Berkas: `dummy-backup.bpos` (format BPOP2, terenkripsi)
- **Password: `dummy12345`**
- Skema DB: v47
- Pakai: Pengaturan > Backup & Restore > Impor, pilih berkas, isi password. PERINGATAN: restore MENIMPA seluruh data di perangkat (pakai build **beta**).
- `dummy-backup.json` = isi mentah (tanpa enkripsi) untuk dibaca.

## Jumlah baris per tabel

| Tabel | Baris |
|---|---|
| app_settings | 16 |
| products | 45 |
| product_groups | 20 |
| product_group_tags | 40 |
| unit_types | 24 |
| product_units | 73 |
| product_barcodes | 68 |
| price_tiers | 99 |
| price_categories | 2 |
| alt_prices | 51 |
| customer_groups | 2 |
| customer_group_prices | 8 |
| customers | 15 |
| transactions | 122 |
| transaction_items | 314 |
| transaction_payments | 124 |
| transaction_adjustment_lines | 1 |
| left_behind_items | 2 |
| borrowed_items | 2 |
| preorder_entries | 3 |
| laci_meja_events | 4 |
| product_aliases | 3 |
| held_orders | 3 |
| reserved_order_numbers | 3 |
| stock_ledger | 372 |
| expenses | 25 |
| loyalty_point_ledger | 55 |
| suppliers | 4 |
| purchases | 6 |
| purchase_items | 24 |
| kasir_permissions | 12 |
| payment_methods | 5 |
| daily_summaries | 59 |
| employees | 3 |
| cash_closings | 4 |
