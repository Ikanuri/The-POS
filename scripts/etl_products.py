#!/usr/bin/env python3
"""ETL import produk dari CSV sistem lama ke database The POS.

Pemakaian:
    python scripts/etl_products.py --csv Products.csv --db the_pos.db [--dry-run]

Catatan: database produksi terenkripsi SQLCipher. Script ini menulis ke DB
sqlite polos; gunakan fitur "Import Produk CSV" di app (Pengaturan) untuk
import langsung ke DB terenkripsi, atau jalankan ini terhadap DB hasil
export development.

Aturan import (sesuai BLUEPRINT_v1):
- Import SEMUA baris, termasuk yang harga jual = 0
- Baris duplikat persis (kode+nama+unit) dilewati
- Produk tanpa barcode dibiarkan kosong (generate via app)
- Unit ID 7 dan 8 legacy = 'Biji', di-merge ke unit ID 1
- Harga jual -> price_tiers minQty=1; harga pokok -> cost_price
"""

import argparse
import csv
import sqlite3
import sys
import uuid
from datetime import datetime

# Mapping nama kolom CSV legacy -> field internal.
# Beberapa alias dicantumkan karena header CSV sistem lama bisa bervariasi.
COLUMN_ALIASES = {
    'name': ['name', 'nama', 'nama_produk', 'product_name', 'namaproduk'],
    'kode_produk': ['kode_produk', 'kode', 'code', 'product_code', 'kodeproduk'],
    'group_id': ['group_id', 'product_group_id', 'group', 'grup', 'kategori_id'],
    'unit_id': ['unit_id', 'unit_type_id', 'satuan_id', 'unit'],
    'barcode': ['barcode', 'kode_barcode'],
    'harga_jual': ['harga_jual', 'hj', 'price', 'harga', 'selling_price'],
    'harga_pokok': ['harga_pokok', 'hpp', 'hp', 'cost', 'cost_price', 'harga_beli'],
    'stok': ['stok', 'stock', 'qty', 'jumlah'],
}

MERGED_UNIT_IDS = {7: 1, 8: 1}  # legacy 7 & 8 = 'Biji' -> ID 1


def resolve_columns(header):
    """Petakan header CSV aktual ke field internal. None jika tidak ketemu."""
    normalized = {h.strip().lower().replace(' ', '_'): h for h in header}
    mapping = {}
    for field, aliases in COLUMN_ALIASES.items():
        mapping[field] = next(
            (normalized[a] for a in aliases if a in normalized), None)
    return mapping


def parse_int(value, default=0):
    if value is None:
        return default
    s = str(value).strip().replace('.', '').replace(',', '').replace('Rp', '')
    try:
        return int(float(s)) if s else default
    except ValueError:
        return default


def run(csv_path, db_path, dry_run=False):
    with open(csv_path, newline='', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        cols = resolve_columns(reader.fieldnames or [])
        if cols['name'] is None:
            sys.exit(f"Kolom nama produk tidak ditemukan. Header: {reader.fieldnames}")
        rows = list(reader)

    print(f"CSV: {len(rows)} baris, mapping kolom: "
          f"{ {k: v for k, v in cols.items() if v} }")

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    now = datetime.now().isoformat(sep=' ', timespec='seconds')

    seen = set()
    stats = {'produk': 0, 'duplikat': 0, 'tanpa_barcode': 0, 'hj_nol': 0}

    for row in rows:
        def val(field):
            col = cols[field]
            return row.get(col, '').strip() if col else ''

        name = val('name')
        if not name:
            continue

        kode = val('kode_produk') or None
        unit_id = parse_int(val('unit_id'), default=1)
        unit_id = MERGED_UNIT_IDS.get(unit_id, unit_id)
        dedup_key = (kode, name.lower(), unit_id)
        if dedup_key in seen:
            stats['duplikat'] += 1
            continue
        seen.add(dedup_key)

        group_id = parse_int(val('group_id'), default=None) if val('group_id') else None
        barcode = val('barcode') or None
        harga_jual = parse_int(val('harga_jual'))
        harga_pokok = parse_int(val('harga_pokok'))
        stok = parse_int(val('stok'))

        if not barcode:
            stats['tanpa_barcode'] += 1
        if harga_jual == 0:
            stats['hj_nol'] += 1

        product_id = str(uuid.uuid4())
        product_unit_id = str(uuid.uuid4())

        if not dry_run:
            cur.execute(
                "INSERT INTO products (id, name, product_group_id, kode_produk,"
                " is_active, created_at, updated_at) VALUES (?,?,?,?,1,?,?)",
                (product_id, name, group_id, kode, now, now))
            cur.execute(
                "INSERT INTO product_units (id, product_id, unit_type_id,"
                " is_base_unit, ratio_to_base, is_non_stock) VALUES (?,?,?,1,1.0,0)",
                (product_unit_id, product_id, unit_id))
            cur.execute(
                "INSERT INTO price_tiers (id, product_unit_id, min_qty, price,"
                " cost_price, created_at) VALUES (?,?,1,?,?,?)",
                (str(uuid.uuid4()), product_unit_id, harga_jual, harga_pokok, now))
            if barcode:
                cur.execute(
                    "INSERT OR IGNORE INTO product_barcodes (id, product_unit_id,"
                    " barcode, is_primary, is_generated) VALUES (?,?,?,1,0)",
                    (str(uuid.uuid4()), product_unit_id, barcode))
            if stok > 0:
                cur.execute(
                    "INSERT INTO stock_ledger (id, product_unit_id, type,"
                    " qty_change, stock_after, note, created_at)"
                    " VALUES (?,?,'opening',?,?,'Import CSV',?)",
                    (str(uuid.uuid4()), product_unit_id, stok, stok, now))

        stats['produk'] += 1

    if dry_run:
        conn.rollback()
        print("DRY RUN — tidak ada yang ditulis.")
    else:
        conn.commit()
    conn.close()

    print(f"Selesai: {stats['produk']} produk diimport, "
          f"{stats['duplikat']} duplikat dilewati, "
          f"{stats['tanpa_barcode']} tanpa barcode, "
          f"{stats['hj_nol']} dengan harga jual 0.")


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--csv', required=True, help='Path file Products.csv')
    ap.add_argument('--db', required=True, help='Path database sqlite tujuan')
    ap.add_argument('--dry-run', action='store_true',
                    help='Validasi saja, tidak menulis ke DB')
    args = ap.parse_args()
    run(args.csv, args.db, args.dry_run)
