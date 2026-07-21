// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSetting(
      {required this.key, required this.value, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<String>? key,
      Value<String>? value,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productGroupIdMeta =
      const VerificationMeta('productGroupId');
  @override
  late final GeneratedColumn<int> productGroupId = GeneratedColumn<int>(
      'product_group_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _kodeProdukMeta =
      const VerificationMeta('kodeProduk');
  @override
  late final GeneratedColumn<String> kodeProduk = GeneratedColumn<String>(
      'kode_produk', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parentProductIdMeta =
      const VerificationMeta('parentProductId');
  @override
  late final GeneratedColumn<String> parentProductId = GeneratedColumn<String>(
      'parent_product_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _markedOutOfStockMeta =
      const VerificationMeta('markedOutOfStock');
  @override
  late final GeneratedColumn<bool> markedOutOfStock = GeneratedColumn<bool>(
      'marked_out_of_stock', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("marked_out_of_stock" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _locallyModifiedMeta =
      const VerificationMeta('locallyModified');
  @override
  late final GeneratedColumn<bool> locallyModified = GeneratedColumn<bool>(
      'locally_modified', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("locally_modified" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        productGroupId,
        kodeProduk,
        parentProductId,
        isActive,
        markedOutOfStock,
        locallyModified,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(Insertable<Product> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('product_group_id')) {
      context.handle(
          _productGroupIdMeta,
          productGroupId.isAcceptableOrUnknown(
              data['product_group_id']!, _productGroupIdMeta));
    }
    if (data.containsKey('kode_produk')) {
      context.handle(
          _kodeProdukMeta,
          kodeProduk.isAcceptableOrUnknown(
              data['kode_produk']!, _kodeProdukMeta));
    }
    if (data.containsKey('parent_product_id')) {
      context.handle(
          _parentProductIdMeta,
          parentProductId.isAcceptableOrUnknown(
              data['parent_product_id']!, _parentProductIdMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('marked_out_of_stock')) {
      context.handle(
          _markedOutOfStockMeta,
          markedOutOfStock.isAcceptableOrUnknown(
              data['marked_out_of_stock']!, _markedOutOfStockMeta));
    }
    if (data.containsKey('locally_modified')) {
      context.handle(
          _locallyModifiedMeta,
          locallyModified.isAcceptableOrUnknown(
              data['locally_modified']!, _locallyModifiedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      productGroupId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}product_group_id']),
      kodeProduk: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kode_produk']),
      parentProductId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}parent_product_id']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      markedOutOfStock: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}marked_out_of_stock'])!,
      locallyModified: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}locally_modified'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final String id;
  final String name;
  final int? productGroupId;
  final String? kodeProduk;

  /// Bila terisi, produk ini adalah VARIAN dari produk induk (mis. Pop Ice →
  /// Coklat). Varian disembunyikan dari katalog utama dan muncul sebagai
  /// pilihan add-on di modal entri item induk.
  final String? parentProductId;
  final bool isActive;

  /// Item 25a — tanda cepat "stok habis" manual, TERPISAH dari sistem stok
  /// resmi (belum diaudit). Diset lewat modal item kasir (bukan form
  /// Produk) untuk akses cepat. Kosmetik di kasir (tidak menonaktifkan
  /// fungsi + — itu wewenang izin "Izinkan Stok Minus"), tapi benar-benar
  /// menonaktifkan tombol tambah di katalog HTML statis.
  final bool markedOutOfStock;
  final bool locallyModified;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Product(
      {required this.id,
      required this.name,
      this.productGroupId,
      this.kodeProduk,
      this.parentProductId,
      required this.isActive,
      required this.markedOutOfStock,
      required this.locallyModified,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || productGroupId != null) {
      map['product_group_id'] = Variable<int>(productGroupId);
    }
    if (!nullToAbsent || kodeProduk != null) {
      map['kode_produk'] = Variable<String>(kodeProduk);
    }
    if (!nullToAbsent || parentProductId != null) {
      map['parent_product_id'] = Variable<String>(parentProductId);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['marked_out_of_stock'] = Variable<bool>(markedOutOfStock);
    map['locally_modified'] = Variable<bool>(locallyModified);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      name: Value(name),
      productGroupId: productGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(productGroupId),
      kodeProduk: kodeProduk == null && nullToAbsent
          ? const Value.absent()
          : Value(kodeProduk),
      parentProductId: parentProductId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentProductId),
      isActive: Value(isActive),
      markedOutOfStock: Value(markedOutOfStock),
      locallyModified: Value(locallyModified),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      productGroupId: serializer.fromJson<int?>(json['productGroupId']),
      kodeProduk: serializer.fromJson<String?>(json['kodeProduk']),
      parentProductId: serializer.fromJson<String?>(json['parentProductId']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      markedOutOfStock: serializer.fromJson<bool>(json['markedOutOfStock']),
      locallyModified: serializer.fromJson<bool>(json['locallyModified']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'productGroupId': serializer.toJson<int?>(productGroupId),
      'kodeProduk': serializer.toJson<String?>(kodeProduk),
      'parentProductId': serializer.toJson<String?>(parentProductId),
      'isActive': serializer.toJson<bool>(isActive),
      'markedOutOfStock': serializer.toJson<bool>(markedOutOfStock),
      'locallyModified': serializer.toJson<bool>(locallyModified),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Product copyWith(
          {String? id,
          String? name,
          Value<int?> productGroupId = const Value.absent(),
          Value<String?> kodeProduk = const Value.absent(),
          Value<String?> parentProductId = const Value.absent(),
          bool? isActive,
          bool? markedOutOfStock,
          bool? locallyModified,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        productGroupId:
            productGroupId.present ? productGroupId.value : this.productGroupId,
        kodeProduk: kodeProduk.present ? kodeProduk.value : this.kodeProduk,
        parentProductId: parentProductId.present
            ? parentProductId.value
            : this.parentProductId,
        isActive: isActive ?? this.isActive,
        markedOutOfStock: markedOutOfStock ?? this.markedOutOfStock,
        locallyModified: locallyModified ?? this.locallyModified,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      productGroupId: data.productGroupId.present
          ? data.productGroupId.value
          : this.productGroupId,
      kodeProduk:
          data.kodeProduk.present ? data.kodeProduk.value : this.kodeProduk,
      parentProductId: data.parentProductId.present
          ? data.parentProductId.value
          : this.parentProductId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      markedOutOfStock: data.markedOutOfStock.present
          ? data.markedOutOfStock.value
          : this.markedOutOfStock,
      locallyModified: data.locallyModified.present
          ? data.locallyModified.value
          : this.locallyModified,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('productGroupId: $productGroupId, ')
          ..write('kodeProduk: $kodeProduk, ')
          ..write('parentProductId: $parentProductId, ')
          ..write('isActive: $isActive, ')
          ..write('markedOutOfStock: $markedOutOfStock, ')
          ..write('locallyModified: $locallyModified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      productGroupId,
      kodeProduk,
      parentProductId,
      isActive,
      markedOutOfStock,
      locallyModified,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.name == this.name &&
          other.productGroupId == this.productGroupId &&
          other.kodeProduk == this.kodeProduk &&
          other.parentProductId == this.parentProductId &&
          other.isActive == this.isActive &&
          other.markedOutOfStock == this.markedOutOfStock &&
          other.locallyModified == this.locallyModified &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> name;
  final Value<int?> productGroupId;
  final Value<String?> kodeProduk;
  final Value<String?> parentProductId;
  final Value<bool> isActive;
  final Value<bool> markedOutOfStock;
  final Value<bool> locallyModified;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.productGroupId = const Value.absent(),
    this.kodeProduk = const Value.absent(),
    this.parentProductId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.markedOutOfStock = const Value.absent(),
    this.locallyModified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String name,
    this.productGroupId = const Value.absent(),
    this.kodeProduk = const Value.absent(),
    this.parentProductId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.markedOutOfStock = const Value.absent(),
    this.locallyModified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? productGroupId,
    Expression<String>? kodeProduk,
    Expression<String>? parentProductId,
    Expression<bool>? isActive,
    Expression<bool>? markedOutOfStock,
    Expression<bool>? locallyModified,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (productGroupId != null) 'product_group_id': productGroupId,
      if (kodeProduk != null) 'kode_produk': kodeProduk,
      if (parentProductId != null) 'parent_product_id': parentProductId,
      if (isActive != null) 'is_active': isActive,
      if (markedOutOfStock != null) 'marked_out_of_stock': markedOutOfStock,
      if (locallyModified != null) 'locally_modified': locallyModified,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int?>? productGroupId,
      Value<String?>? kodeProduk,
      Value<String?>? parentProductId,
      Value<bool>? isActive,
      Value<bool>? markedOutOfStock,
      Value<bool>? locallyModified,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      productGroupId: productGroupId ?? this.productGroupId,
      kodeProduk: kodeProduk ?? this.kodeProduk,
      parentProductId: parentProductId ?? this.parentProductId,
      isActive: isActive ?? this.isActive,
      markedOutOfStock: markedOutOfStock ?? this.markedOutOfStock,
      locallyModified: locallyModified ?? this.locallyModified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (productGroupId.present) {
      map['product_group_id'] = Variable<int>(productGroupId.value);
    }
    if (kodeProduk.present) {
      map['kode_produk'] = Variable<String>(kodeProduk.value);
    }
    if (parentProductId.present) {
      map['parent_product_id'] = Variable<String>(parentProductId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (markedOutOfStock.present) {
      map['marked_out_of_stock'] = Variable<bool>(markedOutOfStock.value);
    }
    if (locallyModified.present) {
      map['locally_modified'] = Variable<bool>(locallyModified.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('productGroupId: $productGroupId, ')
          ..write('kodeProduk: $kodeProduk, ')
          ..write('parentProductId: $parentProductId, ')
          ..write('isActive: $isActive, ')
          ..write('markedOutOfStock: $markedOutOfStock, ')
          ..write('locallyModified: $locallyModified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductGroupsTable extends ProductGroups
    with TableInfo<$ProductGroupsTable, ProductGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_groups';
  @override
  VerificationContext validateIntegrity(Insertable<ProductGroup> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductGroup(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name']),
    );
  }

  @override
  $ProductGroupsTable createAlias(String alias) {
    return $ProductGroupsTable(attachedDatabase, alias);
  }
}

class ProductGroup extends DataClass implements Insertable<ProductGroup> {
  final int id;
  final String? name;
  const ProductGroup({required this.id, this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    return map;
  }

  ProductGroupsCompanion toCompanion(bool nullToAbsent) {
    return ProductGroupsCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
    );
  }

  factory ProductGroup.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductGroup(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String?>(name),
    };
  }

  ProductGroup copyWith(
          {int? id, Value<String?> name = const Value.absent()}) =>
      ProductGroup(
        id: id ?? this.id,
        name: name.present ? name.value : this.name,
      );
  ProductGroup copyWithCompanion(ProductGroupsCompanion data) {
    return ProductGroup(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductGroup(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductGroup && other.id == this.id && other.name == this.name);
}

class ProductGroupsCompanion extends UpdateCompanion<ProductGroup> {
  final Value<int> id;
  final Value<String?> name;
  const ProductGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
  });
  ProductGroupsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
  });
  static Insertable<ProductGroup> custom({
    Expression<int>? id,
    Expression<String>? name,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
    });
  }

  ProductGroupsCompanion copyWith({Value<int>? id, Value<String?>? name}) {
    return ProductGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }
}

class $UnitTypesTable extends UnitTypes
    with TableInfo<$UnitTypesTable, UnitType> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnitTypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _abbrevMeta = const VerificationMeta('abbrev');
  @override
  late final GeneratedColumn<String> abbrev = GeneratedColumn<String>(
      'abbrev', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, name, abbrev];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'unit_types';
  @override
  VerificationContext validateIntegrity(Insertable<UnitType> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('abbrev')) {
      context.handle(_abbrevMeta,
          abbrev.isAcceptableOrUnknown(data['abbrev']!, _abbrevMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UnitType map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UnitType(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      abbrev: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}abbrev']),
    );
  }

  @override
  $UnitTypesTable createAlias(String alias) {
    return $UnitTypesTable(attachedDatabase, alias);
  }
}

class UnitType extends DataClass implements Insertable<UnitType> {
  final int id;
  final String name;
  final String? abbrev;
  const UnitType({required this.id, required this.name, this.abbrev});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || abbrev != null) {
      map['abbrev'] = Variable<String>(abbrev);
    }
    return map;
  }

  UnitTypesCompanion toCompanion(bool nullToAbsent) {
    return UnitTypesCompanion(
      id: Value(id),
      name: Value(name),
      abbrev:
          abbrev == null && nullToAbsent ? const Value.absent() : Value(abbrev),
    );
  }

  factory UnitType.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UnitType(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      abbrev: serializer.fromJson<String?>(json['abbrev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'abbrev': serializer.toJson<String?>(abbrev),
    };
  }

  UnitType copyWith(
          {int? id,
          String? name,
          Value<String?> abbrev = const Value.absent()}) =>
      UnitType(
        id: id ?? this.id,
        name: name ?? this.name,
        abbrev: abbrev.present ? abbrev.value : this.abbrev,
      );
  UnitType copyWithCompanion(UnitTypesCompanion data) {
    return UnitType(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      abbrev: data.abbrev.present ? data.abbrev.value : this.abbrev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UnitType(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('abbrev: $abbrev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, abbrev);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnitType &&
          other.id == this.id &&
          other.name == this.name &&
          other.abbrev == this.abbrev);
}

class UnitTypesCompanion extends UpdateCompanion<UnitType> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> abbrev;
  const UnitTypesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.abbrev = const Value.absent(),
  });
  UnitTypesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.abbrev = const Value.absent(),
  }) : name = Value(name);
  static Insertable<UnitType> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? abbrev,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (abbrev != null) 'abbrev': abbrev,
    });
  }

  UnitTypesCompanion copyWith(
      {Value<int>? id, Value<String>? name, Value<String?>? abbrev}) {
    return UnitTypesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      abbrev: abbrev ?? this.abbrev,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (abbrev.present) {
      map['abbrev'] = Variable<String>(abbrev.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnitTypesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('abbrev: $abbrev')
          ..write(')'))
        .toString();
  }
}

class $ProductUnitsTable extends ProductUnits
    with TableInfo<$ProductUnitsTable, ProductUnit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductUnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _unitTypeIdMeta =
      const VerificationMeta('unitTypeId');
  @override
  late final GeneratedColumn<int> unitTypeId = GeneratedColumn<int>(
      'unit_type_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _isBaseUnitMeta =
      const VerificationMeta('isBaseUnit');
  @override
  late final GeneratedColumn<bool> isBaseUnit = GeneratedColumn<bool>(
      'is_base_unit', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_base_unit" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _ratioToBaseMeta =
      const VerificationMeta('ratioToBase');
  @override
  late final GeneratedColumn<double> ratioToBase = GeneratedColumn<double>(
      'ratio_to_base', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(1.0));
  static const VerificationMeta _isNonStockMeta =
      const VerificationMeta('isNonStock');
  @override
  late final GeneratedColumn<bool> isNonStock = GeneratedColumn<bool>(
      'is_non_stock', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_non_stock" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _minStockMeta =
      const VerificationMeta('minStock');
  @override
  late final GeneratedColumn<int> minStock = GeneratedColumn<int>(
      'min_stock', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        unitTypeId,
        isBaseUnit,
        ratioToBase,
        isNonStock,
        minStock
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_units';
  @override
  VerificationContext validateIntegrity(Insertable<ProductUnit> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('unit_type_id')) {
      context.handle(
          _unitTypeIdMeta,
          unitTypeId.isAcceptableOrUnknown(
              data['unit_type_id']!, _unitTypeIdMeta));
    }
    if (data.containsKey('is_base_unit')) {
      context.handle(
          _isBaseUnitMeta,
          isBaseUnit.isAcceptableOrUnknown(
              data['is_base_unit']!, _isBaseUnitMeta));
    }
    if (data.containsKey('ratio_to_base')) {
      context.handle(
          _ratioToBaseMeta,
          ratioToBase.isAcceptableOrUnknown(
              data['ratio_to_base']!, _ratioToBaseMeta));
    }
    if (data.containsKey('is_non_stock')) {
      context.handle(
          _isNonStockMeta,
          isNonStock.isAcceptableOrUnknown(
              data['is_non_stock']!, _isNonStockMeta));
    }
    if (data.containsKey('min_stock')) {
      context.handle(_minStockMeta,
          minStock.isAcceptableOrUnknown(data['min_stock']!, _minStockMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductUnit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductUnit(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      unitTypeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unit_type_id']),
      isBaseUnit: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_base_unit'])!,
      ratioToBase: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}ratio_to_base'])!,
      isNonStock: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_non_stock'])!,
      minStock: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}min_stock']),
    );
  }

  @override
  $ProductUnitsTable createAlias(String alias) {
    return $ProductUnitsTable(attachedDatabase, alias);
  }
}

class ProductUnit extends DataClass implements Insertable<ProductUnit> {
  final String id;
  final String productId;
  final int? unitTypeId;
  final bool isBaseUnit;
  final double ratioToBase;
  final bool isNonStock;

  /// Item 11: ambang stok menipis, disimpan di baris satuan DASAR saja
  /// (stok selalu dianker ke satuan dasar). null = tidak dipantau.
  final int? minStock;
  const ProductUnit(
      {required this.id,
      required this.productId,
      this.unitTypeId,
      required this.isBaseUnit,
      required this.ratioToBase,
      required this.isNonStock,
      this.minStock});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || unitTypeId != null) {
      map['unit_type_id'] = Variable<int>(unitTypeId);
    }
    map['is_base_unit'] = Variable<bool>(isBaseUnit);
    map['ratio_to_base'] = Variable<double>(ratioToBase);
    map['is_non_stock'] = Variable<bool>(isNonStock);
    if (!nullToAbsent || minStock != null) {
      map['min_stock'] = Variable<int>(minStock);
    }
    return map;
  }

  ProductUnitsCompanion toCompanion(bool nullToAbsent) {
    return ProductUnitsCompanion(
      id: Value(id),
      productId: Value(productId),
      unitTypeId: unitTypeId == null && nullToAbsent
          ? const Value.absent()
          : Value(unitTypeId),
      isBaseUnit: Value(isBaseUnit),
      ratioToBase: Value(ratioToBase),
      isNonStock: Value(isNonStock),
      minStock: minStock == null && nullToAbsent
          ? const Value.absent()
          : Value(minStock),
    );
  }

  factory ProductUnit.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductUnit(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      unitTypeId: serializer.fromJson<int?>(json['unitTypeId']),
      isBaseUnit: serializer.fromJson<bool>(json['isBaseUnit']),
      ratioToBase: serializer.fromJson<double>(json['ratioToBase']),
      isNonStock: serializer.fromJson<bool>(json['isNonStock']),
      minStock: serializer.fromJson<int?>(json['minStock']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'unitTypeId': serializer.toJson<int?>(unitTypeId),
      'isBaseUnit': serializer.toJson<bool>(isBaseUnit),
      'ratioToBase': serializer.toJson<double>(ratioToBase),
      'isNonStock': serializer.toJson<bool>(isNonStock),
      'minStock': serializer.toJson<int?>(minStock),
    };
  }

  ProductUnit copyWith(
          {String? id,
          String? productId,
          Value<int?> unitTypeId = const Value.absent(),
          bool? isBaseUnit,
          double? ratioToBase,
          bool? isNonStock,
          Value<int?> minStock = const Value.absent()}) =>
      ProductUnit(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        unitTypeId: unitTypeId.present ? unitTypeId.value : this.unitTypeId,
        isBaseUnit: isBaseUnit ?? this.isBaseUnit,
        ratioToBase: ratioToBase ?? this.ratioToBase,
        isNonStock: isNonStock ?? this.isNonStock,
        minStock: minStock.present ? minStock.value : this.minStock,
      );
  ProductUnit copyWithCompanion(ProductUnitsCompanion data) {
    return ProductUnit(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      unitTypeId:
          data.unitTypeId.present ? data.unitTypeId.value : this.unitTypeId,
      isBaseUnit:
          data.isBaseUnit.present ? data.isBaseUnit.value : this.isBaseUnit,
      ratioToBase:
          data.ratioToBase.present ? data.ratioToBase.value : this.ratioToBase,
      isNonStock:
          data.isNonStock.present ? data.isNonStock.value : this.isNonStock,
      minStock: data.minStock.present ? data.minStock.value : this.minStock,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductUnit(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('unitTypeId: $unitTypeId, ')
          ..write('isBaseUnit: $isBaseUnit, ')
          ..write('ratioToBase: $ratioToBase, ')
          ..write('isNonStock: $isNonStock, ')
          ..write('minStock: $minStock')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, productId, unitTypeId, isBaseUnit, ratioToBase, isNonStock, minStock);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductUnit &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.unitTypeId == this.unitTypeId &&
          other.isBaseUnit == this.isBaseUnit &&
          other.ratioToBase == this.ratioToBase &&
          other.isNonStock == this.isNonStock &&
          other.minStock == this.minStock);
}

class ProductUnitsCompanion extends UpdateCompanion<ProductUnit> {
  final Value<String> id;
  final Value<String> productId;
  final Value<int?> unitTypeId;
  final Value<bool> isBaseUnit;
  final Value<double> ratioToBase;
  final Value<bool> isNonStock;
  final Value<int?> minStock;
  final Value<int> rowid;
  const ProductUnitsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.unitTypeId = const Value.absent(),
    this.isBaseUnit = const Value.absent(),
    this.ratioToBase = const Value.absent(),
    this.isNonStock = const Value.absent(),
    this.minStock = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductUnitsCompanion.insert({
    required String id,
    required String productId,
    this.unitTypeId = const Value.absent(),
    this.isBaseUnit = const Value.absent(),
    this.ratioToBase = const Value.absent(),
    this.isNonStock = const Value.absent(),
    this.minStock = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId);
  static Insertable<ProductUnit> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<int>? unitTypeId,
    Expression<bool>? isBaseUnit,
    Expression<double>? ratioToBase,
    Expression<bool>? isNonStock,
    Expression<int>? minStock,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (unitTypeId != null) 'unit_type_id': unitTypeId,
      if (isBaseUnit != null) 'is_base_unit': isBaseUnit,
      if (ratioToBase != null) 'ratio_to_base': ratioToBase,
      if (isNonStock != null) 'is_non_stock': isNonStock,
      if (minStock != null) 'min_stock': minStock,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductUnitsCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<int?>? unitTypeId,
      Value<bool>? isBaseUnit,
      Value<double>? ratioToBase,
      Value<bool>? isNonStock,
      Value<int?>? minStock,
      Value<int>? rowid}) {
    return ProductUnitsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      unitTypeId: unitTypeId ?? this.unitTypeId,
      isBaseUnit: isBaseUnit ?? this.isBaseUnit,
      ratioToBase: ratioToBase ?? this.ratioToBase,
      isNonStock: isNonStock ?? this.isNonStock,
      minStock: minStock ?? this.minStock,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (unitTypeId.present) {
      map['unit_type_id'] = Variable<int>(unitTypeId.value);
    }
    if (isBaseUnit.present) {
      map['is_base_unit'] = Variable<bool>(isBaseUnit.value);
    }
    if (ratioToBase.present) {
      map['ratio_to_base'] = Variable<double>(ratioToBase.value);
    }
    if (isNonStock.present) {
      map['is_non_stock'] = Variable<bool>(isNonStock.value);
    }
    if (minStock.present) {
      map['min_stock'] = Variable<int>(minStock.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductUnitsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('unitTypeId: $unitTypeId, ')
          ..write('isBaseUnit: $isBaseUnit, ')
          ..write('ratioToBase: $ratioToBase, ')
          ..write('isNonStock: $isNonStock, ')
          ..write('minStock: $minStock, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductBarcodesTable extends ProductBarcodes
    with TableInfo<$ProductBarcodesTable, ProductBarcode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductBarcodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES product_units (id)'));
  static const VerificationMeta _barcodeMeta =
      const VerificationMeta('barcode');
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
      'barcode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _isPrimaryMeta =
      const VerificationMeta('isPrimary');
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
      'is_primary', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_primary" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isGeneratedMeta =
      const VerificationMeta('isGenerated');
  @override
  late final GeneratedColumn<bool> isGenerated = GeneratedColumn<bool>(
      'is_generated', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_generated" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, productUnitId, barcode, isPrimary, isGenerated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_barcodes';
  @override
  VerificationContext validateIntegrity(Insertable<ProductBarcode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(_barcodeMeta,
          barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta));
    } else if (isInserting) {
      context.missing(_barcodeMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(_isPrimaryMeta,
          isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta));
    }
    if (data.containsKey('is_generated')) {
      context.handle(
          _isGeneratedMeta,
          isGenerated.isAcceptableOrUnknown(
              data['is_generated']!, _isGeneratedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductBarcode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductBarcode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      barcode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}barcode'])!,
      isPrimary: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_primary'])!,
      isGenerated: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_generated'])!,
    );
  }

  @override
  $ProductBarcodesTable createAlias(String alias) {
    return $ProductBarcodesTable(attachedDatabase, alias);
  }
}

class ProductBarcode extends DataClass implements Insertable<ProductBarcode> {
  final String id;
  final String productUnitId;
  final String barcode;
  final bool isPrimary;
  final bool isGenerated;
  const ProductBarcode(
      {required this.id,
      required this.productUnitId,
      required this.barcode,
      required this.isPrimary,
      required this.isGenerated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['barcode'] = Variable<String>(barcode);
    map['is_primary'] = Variable<bool>(isPrimary);
    map['is_generated'] = Variable<bool>(isGenerated);
    return map;
  }

  ProductBarcodesCompanion toCompanion(bool nullToAbsent) {
    return ProductBarcodesCompanion(
      id: Value(id),
      productUnitId: Value(productUnitId),
      barcode: Value(barcode),
      isPrimary: Value(isPrimary),
      isGenerated: Value(isGenerated),
    );
  }

  factory ProductBarcode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductBarcode(
      id: serializer.fromJson<String>(json['id']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      barcode: serializer.fromJson<String>(json['barcode']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
      isGenerated: serializer.fromJson<bool>(json['isGenerated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'barcode': serializer.toJson<String>(barcode),
      'isPrimary': serializer.toJson<bool>(isPrimary),
      'isGenerated': serializer.toJson<bool>(isGenerated),
    };
  }

  ProductBarcode copyWith(
          {String? id,
          String? productUnitId,
          String? barcode,
          bool? isPrimary,
          bool? isGenerated}) =>
      ProductBarcode(
        id: id ?? this.id,
        productUnitId: productUnitId ?? this.productUnitId,
        barcode: barcode ?? this.barcode,
        isPrimary: isPrimary ?? this.isPrimary,
        isGenerated: isGenerated ?? this.isGenerated,
      );
  ProductBarcode copyWithCompanion(ProductBarcodesCompanion data) {
    return ProductBarcode(
      id: data.id.present ? data.id.value : this.id,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      isGenerated:
          data.isGenerated.present ? data.isGenerated.value : this.isGenerated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductBarcode(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('barcode: $barcode, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('isGenerated: $isGenerated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, productUnitId, barcode, isPrimary, isGenerated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductBarcode &&
          other.id == this.id &&
          other.productUnitId == this.productUnitId &&
          other.barcode == this.barcode &&
          other.isPrimary == this.isPrimary &&
          other.isGenerated == this.isGenerated);
}

class ProductBarcodesCompanion extends UpdateCompanion<ProductBarcode> {
  final Value<String> id;
  final Value<String> productUnitId;
  final Value<String> barcode;
  final Value<bool> isPrimary;
  final Value<bool> isGenerated;
  final Value<int> rowid;
  const ProductBarcodesCompanion({
    this.id = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.barcode = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.isGenerated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductBarcodesCompanion.insert({
    required String id,
    required String productUnitId,
    required String barcode,
    this.isPrimary = const Value.absent(),
    this.isGenerated = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productUnitId = Value(productUnitId),
        barcode = Value(barcode);
  static Insertable<ProductBarcode> custom({
    Expression<String>? id,
    Expression<String>? productUnitId,
    Expression<String>? barcode,
    Expression<bool>? isPrimary,
    Expression<bool>? isGenerated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (barcode != null) 'barcode': barcode,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (isGenerated != null) 'is_generated': isGenerated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductBarcodesCompanion copyWith(
      {Value<String>? id,
      Value<String>? productUnitId,
      Value<String>? barcode,
      Value<bool>? isPrimary,
      Value<bool>? isGenerated,
      Value<int>? rowid}) {
    return ProductBarcodesCompanion(
      id: id ?? this.id,
      productUnitId: productUnitId ?? this.productUnitId,
      barcode: barcode ?? this.barcode,
      isPrimary: isPrimary ?? this.isPrimary,
      isGenerated: isGenerated ?? this.isGenerated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (isGenerated.present) {
      map['is_generated'] = Variable<bool>(isGenerated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductBarcodesCompanion(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('barcode: $barcode, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('isGenerated: $isGenerated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PriceTiersTable extends PriceTiers
    with TableInfo<$PriceTiersTable, PriceTier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PriceTiersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES product_units (id)'));
  static const VerificationMeta _minQtyMeta = const VerificationMeta('minQty');
  @override
  late final GeneratedColumn<int> minQty = GeneratedColumn<int>(
      'min_qty', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
      'price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _costPriceMeta =
      const VerificationMeta('costPrice');
  @override
  late final GeneratedColumn<int> costPrice = GeneratedColumn<int>(
      'cost_price', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, productUnitId, minQty, price, costPrice, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'price_tiers';
  @override
  VerificationContext validateIntegrity(Insertable<PriceTier> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('min_qty')) {
      context.handle(_minQtyMeta,
          minQty.isAcceptableOrUnknown(data['min_qty']!, _minQtyMeta));
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('cost_price')) {
      context.handle(_costPriceMeta,
          costPrice.isAcceptableOrUnknown(data['cost_price']!, _costPriceMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PriceTier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PriceTier(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      minQty: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}min_qty'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price'])!,
      costPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cost_price'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PriceTiersTable createAlias(String alias) {
    return $PriceTiersTable(attachedDatabase, alias);
  }
}

class PriceTier extends DataClass implements Insertable<PriceTier> {
  final String id;
  final String productUnitId;
  final int minQty;
  final int price;
  final int costPrice;
  final DateTime createdAt;
  const PriceTier(
      {required this.id,
      required this.productUnitId,
      required this.minQty,
      required this.price,
      required this.costPrice,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['min_qty'] = Variable<int>(minQty);
    map['price'] = Variable<int>(price);
    map['cost_price'] = Variable<int>(costPrice);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PriceTiersCompanion toCompanion(bool nullToAbsent) {
    return PriceTiersCompanion(
      id: Value(id),
      productUnitId: Value(productUnitId),
      minQty: Value(minQty),
      price: Value(price),
      costPrice: Value(costPrice),
      createdAt: Value(createdAt),
    );
  }

  factory PriceTier.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PriceTier(
      id: serializer.fromJson<String>(json['id']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      minQty: serializer.fromJson<int>(json['minQty']),
      price: serializer.fromJson<int>(json['price']),
      costPrice: serializer.fromJson<int>(json['costPrice']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'minQty': serializer.toJson<int>(minQty),
      'price': serializer.toJson<int>(price),
      'costPrice': serializer.toJson<int>(costPrice),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PriceTier copyWith(
          {String? id,
          String? productUnitId,
          int? minQty,
          int? price,
          int? costPrice,
          DateTime? createdAt}) =>
      PriceTier(
        id: id ?? this.id,
        productUnitId: productUnitId ?? this.productUnitId,
        minQty: minQty ?? this.minQty,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        createdAt: createdAt ?? this.createdAt,
      );
  PriceTier copyWithCompanion(PriceTiersCompanion data) {
    return PriceTier(
      id: data.id.present ? data.id.value : this.id,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      minQty: data.minQty.present ? data.minQty.value : this.minQty,
      price: data.price.present ? data.price.value : this.price,
      costPrice: data.costPrice.present ? data.costPrice.value : this.costPrice,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PriceTier(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('minQty: $minQty, ')
          ..write('price: $price, ')
          ..write('costPrice: $costPrice, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, productUnitId, minQty, price, costPrice, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PriceTier &&
          other.id == this.id &&
          other.productUnitId == this.productUnitId &&
          other.minQty == this.minQty &&
          other.price == this.price &&
          other.costPrice == this.costPrice &&
          other.createdAt == this.createdAt);
}

class PriceTiersCompanion extends UpdateCompanion<PriceTier> {
  final Value<String> id;
  final Value<String> productUnitId;
  final Value<int> minQty;
  final Value<int> price;
  final Value<int> costPrice;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PriceTiersCompanion({
    this.id = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.minQty = const Value.absent(),
    this.price = const Value.absent(),
    this.costPrice = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PriceTiersCompanion.insert({
    required String id,
    required String productUnitId,
    this.minQty = const Value.absent(),
    required int price,
    this.costPrice = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productUnitId = Value(productUnitId),
        price = Value(price);
  static Insertable<PriceTier> custom({
    Expression<String>? id,
    Expression<String>? productUnitId,
    Expression<int>? minQty,
    Expression<int>? price,
    Expression<int>? costPrice,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (minQty != null) 'min_qty': minQty,
      if (price != null) 'price': price,
      if (costPrice != null) 'cost_price': costPrice,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PriceTiersCompanion copyWith(
      {Value<String>? id,
      Value<String>? productUnitId,
      Value<int>? minQty,
      Value<int>? price,
      Value<int>? costPrice,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PriceTiersCompanion(
      id: id ?? this.id,
      productUnitId: productUnitId ?? this.productUnitId,
      minQty: minQty ?? this.minQty,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (minQty.present) {
      map['min_qty'] = Variable<int>(minQty.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (costPrice.present) {
      map['cost_price'] = Variable<int>(costPrice.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PriceTiersCompanion(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('minQty: $minQty, ')
          ..write('price: $price, ')
          ..write('costPrice: $costPrice, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AltPricesTable extends AltPrices
    with TableInfo<$AltPricesTable, AltPrice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AltPricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES product_units (id)'));
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
      'price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, productUnitId, label, price, createdAt, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alt_prices';
  @override
  VerificationContext validateIntegrity(Insertable<AltPrice> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AltPrice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AltPrice(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $AltPricesTable createAlias(String alias) {
    return $AltPricesTable(attachedDatabase, alias);
  }
}

class AltPrice extends DataClass implements Insertable<AltPrice> {
  final String id;
  final String productUnitId;
  final String label;
  final int price;
  final DateTime createdAt;
  final int sortOrder;
  const AltPrice(
      {required this.id,
      required this.productUnitId,
      required this.label,
      required this.price,
      required this.createdAt,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['label'] = Variable<String>(label);
    map['price'] = Variable<int>(price);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  AltPricesCompanion toCompanion(bool nullToAbsent) {
    return AltPricesCompanion(
      id: Value(id),
      productUnitId: Value(productUnitId),
      label: Value(label),
      price: Value(price),
      createdAt: Value(createdAt),
      sortOrder: Value(sortOrder),
    );
  }

  factory AltPrice.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AltPrice(
      id: serializer.fromJson<String>(json['id']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      label: serializer.fromJson<String>(json['label']),
      price: serializer.fromJson<int>(json['price']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'label': serializer.toJson<String>(label),
      'price': serializer.toJson<int>(price),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  AltPrice copyWith(
          {String? id,
          String? productUnitId,
          String? label,
          int? price,
          DateTime? createdAt,
          int? sortOrder}) =>
      AltPrice(
        id: id ?? this.id,
        productUnitId: productUnitId ?? this.productUnitId,
        label: label ?? this.label,
        price: price ?? this.price,
        createdAt: createdAt ?? this.createdAt,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  AltPrice copyWithCompanion(AltPricesCompanion data) {
    return AltPrice(
      id: data.id.present ? data.id.value : this.id,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      label: data.label.present ? data.label.value : this.label,
      price: data.price.present ? data.price.value : this.price,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AltPrice(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('label: $label, ')
          ..write('price: $price, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, productUnitId, label, price, createdAt, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AltPrice &&
          other.id == this.id &&
          other.productUnitId == this.productUnitId &&
          other.label == this.label &&
          other.price == this.price &&
          other.createdAt == this.createdAt &&
          other.sortOrder == this.sortOrder);
}

class AltPricesCompanion extends UpdateCompanion<AltPrice> {
  final Value<String> id;
  final Value<String> productUnitId;
  final Value<String> label;
  final Value<int> price;
  final Value<DateTime> createdAt;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const AltPricesCompanion({
    this.id = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.label = const Value.absent(),
    this.price = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AltPricesCompanion.insert({
    required String id,
    required String productUnitId,
    required String label,
    required int price,
    this.createdAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productUnitId = Value(productUnitId),
        label = Value(label),
        price = Value(price);
  static Insertable<AltPrice> custom({
    Expression<String>? id,
    Expression<String>? productUnitId,
    Expression<String>? label,
    Expression<int>? price,
    Expression<DateTime>? createdAt,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (label != null) 'label': label,
      if (price != null) 'price': price,
      if (createdAt != null) 'created_at': createdAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AltPricesCompanion copyWith(
      {Value<String>? id,
      Value<String>? productUnitId,
      Value<String>? label,
      Value<int>? price,
      Value<DateTime>? createdAt,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return AltPricesCompanion(
      id: id ?? this.id,
      productUnitId: productUnitId ?? this.productUnitId,
      label: label ?? this.label,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AltPricesCompanion(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('label: $label, ')
          ..write('price: $price, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomerGroupsTable extends CustomerGroups
    with TableInfo<$CustomerGroupsTable, CustomerGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomerGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
      'color', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, name, color];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customer_groups';
  @override
  VerificationContext validateIntegrity(Insertable<CustomerGroup> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomerGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerGroup(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color']),
    );
  }

  @override
  $CustomerGroupsTable createAlias(String alias) {
    return $CustomerGroupsTable(attachedDatabase, alias);
  }
}

class CustomerGroup extends DataClass implements Insertable<CustomerGroup> {
  final String id;
  final String name;
  final String? color;
  const CustomerGroup({required this.id, required this.name, this.color});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    return map;
  }

  CustomerGroupsCompanion toCompanion(bool nullToAbsent) {
    return CustomerGroupsCompanion(
      id: Value(id),
      name: Value(name),
      color:
          color == null && nullToAbsent ? const Value.absent() : Value(color),
    );
  }

  factory CustomerGroup.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerGroup(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String?>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String?>(color),
    };
  }

  CustomerGroup copyWith(
          {String? id,
          String? name,
          Value<String?> color = const Value.absent()}) =>
      CustomerGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color.present ? color.value : this.color,
      );
  CustomerGroup copyWithCompanion(CustomerGroupsCompanion data) {
    return CustomerGroup(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerGroup(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerGroup &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color);
}

class CustomerGroupsCompanion extends UpdateCompanion<CustomerGroup> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> color;
  final Value<int> rowid;
  const CustomerGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomerGroupsCompanion.insert({
    required String id,
    required String name,
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<CustomerGroup> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomerGroupsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? color,
      Value<int>? rowid}) {
    return CustomerGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomerGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomerGroupPricesTable extends CustomerGroupPrices
    with TableInfo<$CustomerGroupPricesTable, CustomerGroupPrice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomerGroupPricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES product_units (id)'));
  static const VerificationMeta _customerGroupIdMeta =
      const VerificationMeta('customerGroupId');
  @override
  late final GeneratedColumn<String> customerGroupId = GeneratedColumn<String>(
      'customer_group_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES customer_groups (id)'));
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
      'price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, productUnitId, customerGroupId, price];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customer_group_prices';
  @override
  VerificationContext validateIntegrity(Insertable<CustomerGroupPrice> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('customer_group_id')) {
      context.handle(
          _customerGroupIdMeta,
          customerGroupId.isAcceptableOrUnknown(
              data['customer_group_id']!, _customerGroupIdMeta));
    } else if (isInserting) {
      context.missing(_customerGroupIdMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {productUnitId, customerGroupId},
      ];
  @override
  CustomerGroupPrice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerGroupPrice(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      customerGroupId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}customer_group_id'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price'])!,
    );
  }

  @override
  $CustomerGroupPricesTable createAlias(String alias) {
    return $CustomerGroupPricesTable(attachedDatabase, alias);
  }
}

class CustomerGroupPrice extends DataClass
    implements Insertable<CustomerGroupPrice> {
  final String id;
  final String productUnitId;
  final String customerGroupId;
  final int price;
  const CustomerGroupPrice(
      {required this.id,
      required this.productUnitId,
      required this.customerGroupId,
      required this.price});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['customer_group_id'] = Variable<String>(customerGroupId);
    map['price'] = Variable<int>(price);
    return map;
  }

  CustomerGroupPricesCompanion toCompanion(bool nullToAbsent) {
    return CustomerGroupPricesCompanion(
      id: Value(id),
      productUnitId: Value(productUnitId),
      customerGroupId: Value(customerGroupId),
      price: Value(price),
    );
  }

  factory CustomerGroupPrice.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerGroupPrice(
      id: serializer.fromJson<String>(json['id']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      customerGroupId: serializer.fromJson<String>(json['customerGroupId']),
      price: serializer.fromJson<int>(json['price']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'customerGroupId': serializer.toJson<String>(customerGroupId),
      'price': serializer.toJson<int>(price),
    };
  }

  CustomerGroupPrice copyWith(
          {String? id,
          String? productUnitId,
          String? customerGroupId,
          int? price}) =>
      CustomerGroupPrice(
        id: id ?? this.id,
        productUnitId: productUnitId ?? this.productUnitId,
        customerGroupId: customerGroupId ?? this.customerGroupId,
        price: price ?? this.price,
      );
  CustomerGroupPrice copyWithCompanion(CustomerGroupPricesCompanion data) {
    return CustomerGroupPrice(
      id: data.id.present ? data.id.value : this.id,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      customerGroupId: data.customerGroupId.present
          ? data.customerGroupId.value
          : this.customerGroupId,
      price: data.price.present ? data.price.value : this.price,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerGroupPrice(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('customerGroupId: $customerGroupId, ')
          ..write('price: $price')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productUnitId, customerGroupId, price);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerGroupPrice &&
          other.id == this.id &&
          other.productUnitId == this.productUnitId &&
          other.customerGroupId == this.customerGroupId &&
          other.price == this.price);
}

class CustomerGroupPricesCompanion extends UpdateCompanion<CustomerGroupPrice> {
  final Value<String> id;
  final Value<String> productUnitId;
  final Value<String> customerGroupId;
  final Value<int> price;
  final Value<int> rowid;
  const CustomerGroupPricesCompanion({
    this.id = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.customerGroupId = const Value.absent(),
    this.price = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomerGroupPricesCompanion.insert({
    required String id,
    required String productUnitId,
    required String customerGroupId,
    required int price,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productUnitId = Value(productUnitId),
        customerGroupId = Value(customerGroupId),
        price = Value(price);
  static Insertable<CustomerGroupPrice> custom({
    Expression<String>? id,
    Expression<String>? productUnitId,
    Expression<String>? customerGroupId,
    Expression<int>? price,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (customerGroupId != null) 'customer_group_id': customerGroupId,
      if (price != null) 'price': price,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomerGroupPricesCompanion copyWith(
      {Value<String>? id,
      Value<String>? productUnitId,
      Value<String>? customerGroupId,
      Value<int>? price,
      Value<int>? rowid}) {
    return CustomerGroupPricesCompanion(
      id: id ?? this.id,
      productUnitId: productUnitId ?? this.productUnitId,
      customerGroupId: customerGroupId ?? this.customerGroupId,
      price: price ?? this.price,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (customerGroupId.present) {
      map['customer_group_id'] = Variable<String>(customerGroupId.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomerGroupPricesCompanion(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('customerGroupId: $customerGroupId, ')
          ..write('price: $price, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, Customer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customerGroupIdMeta =
      const VerificationMeta('customerGroupId');
  @override
  late final GeneratedColumn<String> customerGroupId = GeneratedColumn<String>(
      'customer_group_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _creditLimitMeta =
      const VerificationMeta('creditLimit');
  @override
  late final GeneratedColumn<int> creditLimit = GeneratedColumn<int>(
      'credit_limit', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _outstandingDebtMeta =
      const VerificationMeta('outstandingDebt');
  @override
  late final GeneratedColumn<int> outstandingDebt = GeneratedColumn<int>(
      'outstanding_debt', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _loyaltyPointsMeta =
      const VerificationMeta('loyaltyPoints');
  @override
  late final GeneratedColumn<int> loyaltyPoints = GeneratedColumn<int>(
      'loyalty_points', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        phone,
        address,
        customerGroupId,
        creditLimit,
        outstandingDebt,
        loyaltyPoints,
        notes,
        isActive,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(Insertable<Customer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    }
    if (data.containsKey('customer_group_id')) {
      context.handle(
          _customerGroupIdMeta,
          customerGroupId.isAcceptableOrUnknown(
              data['customer_group_id']!, _customerGroupIdMeta));
    }
    if (data.containsKey('credit_limit')) {
      context.handle(
          _creditLimitMeta,
          creditLimit.isAcceptableOrUnknown(
              data['credit_limit']!, _creditLimitMeta));
    }
    if (data.containsKey('outstanding_debt')) {
      context.handle(
          _outstandingDebtMeta,
          outstandingDebt.isAcceptableOrUnknown(
              data['outstanding_debt']!, _outstandingDebtMeta));
    }
    if (data.containsKey('loyalty_points')) {
      context.handle(
          _loyaltyPointsMeta,
          loyaltyPoints.isAcceptableOrUnknown(
              data['loyalty_points']!, _loyaltyPointsMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Customer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Customer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address']),
      customerGroupId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}customer_group_id']),
      creditLimit: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}credit_limit'])!,
      outstandingDebt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}outstanding_debt'])!,
      loyaltyPoints: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}loyalty_points'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }
}

class Customer extends DataClass implements Insertable<Customer> {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? customerGroupId;
  final int creditLimit;
  final int outstandingDebt;
  final int loyaltyPoints;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Customer(
      {required this.id,
      required this.name,
      this.phone,
      this.address,
      this.customerGroupId,
      required this.creditLimit,
      required this.outstandingDebt,
      required this.loyaltyPoints,
      this.notes,
      required this.isActive,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || customerGroupId != null) {
      map['customer_group_id'] = Variable<String>(customerGroupId);
    }
    map['credit_limit'] = Variable<int>(creditLimit);
    map['outstanding_debt'] = Variable<int>(outstandingDebt);
    map['loyalty_points'] = Variable<int>(loyaltyPoints);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      name: Value(name),
      phone:
          phone == null && nullToAbsent ? const Value.absent() : Value(phone),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      customerGroupId: customerGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerGroupId),
      creditLimit: Value(creditLimit),
      outstandingDebt: Value(outstandingDebt),
      loyaltyPoints: Value(loyaltyPoints),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Customer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Customer(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      address: serializer.fromJson<String?>(json['address']),
      customerGroupId: serializer.fromJson<String?>(json['customerGroupId']),
      creditLimit: serializer.fromJson<int>(json['creditLimit']),
      outstandingDebt: serializer.fromJson<int>(json['outstandingDebt']),
      loyaltyPoints: serializer.fromJson<int>(json['loyaltyPoints']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'address': serializer.toJson<String?>(address),
      'customerGroupId': serializer.toJson<String?>(customerGroupId),
      'creditLimit': serializer.toJson<int>(creditLimit),
      'outstandingDebt': serializer.toJson<int>(outstandingDebt),
      'loyaltyPoints': serializer.toJson<int>(loyaltyPoints),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Customer copyWith(
          {String? id,
          String? name,
          Value<String?> phone = const Value.absent(),
          Value<String?> address = const Value.absent(),
          Value<String?> customerGroupId = const Value.absent(),
          int? creditLimit,
          int? outstandingDebt,
          int? loyaltyPoints,
          Value<String?> notes = const Value.absent(),
          bool? isActive,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Customer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone.present ? phone.value : this.phone,
        address: address.present ? address.value : this.address,
        customerGroupId: customerGroupId.present
            ? customerGroupId.value
            : this.customerGroupId,
        creditLimit: creditLimit ?? this.creditLimit,
        outstandingDebt: outstandingDebt ?? this.outstandingDebt,
        loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
        notes: notes.present ? notes.value : this.notes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Customer copyWithCompanion(CustomersCompanion data) {
    return Customer(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      address: data.address.present ? data.address.value : this.address,
      customerGroupId: data.customerGroupId.present
          ? data.customerGroupId.value
          : this.customerGroupId,
      creditLimit:
          data.creditLimit.present ? data.creditLimit.value : this.creditLimit,
      outstandingDebt: data.outstandingDebt.present
          ? data.outstandingDebt.value
          : this.outstandingDebt,
      loyaltyPoints: data.loyaltyPoints.present
          ? data.loyaltyPoints.value
          : this.loyaltyPoints,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Customer(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('customerGroupId: $customerGroupId, ')
          ..write('creditLimit: $creditLimit, ')
          ..write('outstandingDebt: $outstandingDebt, ')
          ..write('loyaltyPoints: $loyaltyPoints, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      phone,
      address,
      customerGroupId,
      creditLimit,
      outstandingDebt,
      loyaltyPoints,
      notes,
      isActive,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Customer &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.address == this.address &&
          other.customerGroupId == this.customerGroupId &&
          other.creditLimit == this.creditLimit &&
          other.outstandingDebt == this.outstandingDebt &&
          other.loyaltyPoints == this.loyaltyPoints &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CustomersCompanion extends UpdateCompanion<Customer> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> address;
  final Value<String?> customerGroupId;
  final Value<int> creditLimit;
  final Value<int> outstandingDebt;
  final Value<int> loyaltyPoints;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.customerGroupId = const Value.absent(),
    this.creditLimit = const Value.absent(),
    this.outstandingDebt = const Value.absent(),
    this.loyaltyPoints = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomersCompanion.insert({
    required String id,
    required String name,
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.customerGroupId = const Value.absent(),
    this.creditLimit = const Value.absent(),
    this.outstandingDebt = const Value.absent(),
    this.loyaltyPoints = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<Customer> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? address,
    Expression<String>? customerGroupId,
    Expression<int>? creditLimit,
    Expression<int>? outstandingDebt,
    Expression<int>? loyaltyPoints,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (customerGroupId != null) 'customer_group_id': customerGroupId,
      if (creditLimit != null) 'credit_limit': creditLimit,
      if (outstandingDebt != null) 'outstanding_debt': outstandingDebt,
      if (loyaltyPoints != null) 'loyalty_points': loyaltyPoints,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomersCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? phone,
      Value<String?>? address,
      Value<String?>? customerGroupId,
      Value<int>? creditLimit,
      Value<int>? outstandingDebt,
      Value<int>? loyaltyPoints,
      Value<String?>? notes,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CustomersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      customerGroupId: customerGroupId ?? this.customerGroupId,
      creditLimit: creditLimit ?? this.creditLimit,
      outstandingDebt: outstandingDebt ?? this.outstandingDebt,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (customerGroupId.present) {
      map['customer_group_id'] = Variable<String>(customerGroupId.value);
    }
    if (creditLimit.present) {
      map['credit_limit'] = Variable<int>(creditLimit.value);
    }
    if (outstandingDebt.present) {
      map['outstanding_debt'] = Variable<int>(outstandingDebt.value);
    }
    if (loyaltyPoints.present) {
      map['loyalty_points'] = Variable<int>(loyaltyPoints.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('customerGroupId: $customerGroupId, ')
          ..write('creditLimit: $creditLimit, ')
          ..write('outstandingDebt: $outstandingDebt, ')
          ..write('loyaltyPoints: $loyaltyPoints, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
      'local_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _kasirIdMeta =
      const VerificationMeta('kasirId');
  @override
  late final GeneratedColumn<String> kasirId = GeneratedColumn<String>(
      'kasir_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customerIdMeta =
      const VerificationMeta('customerId');
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
      'customer_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customerNameMeta =
      const VerificationMeta('customerName');
  @override
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
      'customer_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<int> total = GeneratedColumn<int>(
      'total', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _paidMeta = const VerificationMeta('paid');
  @override
  late final GeneratedColumn<int> paid = GeneratedColumn<int>(
      'paid', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _changeAmountMeta =
      const VerificationMeta('changeAmount');
  @override
  late final GeneratedColumn<int> changeAmount = GeneratedColumn<int>(
      'change_amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _internalNoteMeta =
      const VerificationMeta('internalNote');
  @override
  late final GeneratedColumn<String> internalNote = GeneratedColumn<String>(
      'internal_note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _strukNoteMeta =
      const VerificationMeta('strukNote');
  @override
  late final GeneratedColumn<String> strukNote = GeneratedColumn<String>(
      'struk_note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _employeeNameMeta =
      const VerificationMeta('employeeName');
  @override
  late final GeneratedColumn<String> employeeName = GeneratedColumn<String>(
      'employee_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pointsEarnedMeta =
      const VerificationMeta('pointsEarned');
  @override
  late final GeneratedColumn<int> pointsEarned = GeneratedColumn<int>(
      'points_earned', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _changeTakenMeta =
      const VerificationMeta('changeTaken');
  @override
  late final GeneratedColumn<bool> changeTaken = GeneratedColumn<bool>(
      'change_taken', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("change_taken" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _checkedItemIdsMeta =
      const VerificationMeta('checkedItemIds');
  @override
  late final GeneratedColumn<String> checkedItemIds = GeneratedColumn<String>(
      'checked_item_ids', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        localId,
        kasirId,
        customerId,
        customerName,
        status,
        total,
        paid,
        changeAmount,
        paymentMethod,
        internalNote,
        strukNote,
        employeeName,
        pointsEarned,
        changeTaken,
        checkedItemIds,
        createdAt,
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(Insertable<Transaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('kasir_id')) {
      context.handle(_kasirIdMeta,
          kasirId.isAcceptableOrUnknown(data['kasir_id']!, _kasirIdMeta));
    }
    if (data.containsKey('customer_id')) {
      context.handle(
          _customerIdMeta,
          customerId.isAcceptableOrUnknown(
              data['customer_id']!, _customerIdMeta));
    }
    if (data.containsKey('customer_name')) {
      context.handle(
          _customerNameMeta,
          customerName.isAcceptableOrUnknown(
              data['customer_name']!, _customerNameMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('total')) {
      context.handle(
          _totalMeta, total.isAcceptableOrUnknown(data['total']!, _totalMeta));
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    if (data.containsKey('paid')) {
      context.handle(
          _paidMeta, paid.isAcceptableOrUnknown(data['paid']!, _paidMeta));
    } else if (isInserting) {
      context.missing(_paidMeta);
    }
    if (data.containsKey('change_amount')) {
      context.handle(
          _changeAmountMeta,
          changeAmount.isAcceptableOrUnknown(
              data['change_amount']!, _changeAmountMeta));
    } else if (isInserting) {
      context.missing(_changeAmountMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
          _paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(
              data['payment_method']!, _paymentMethodMeta));
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('internal_note')) {
      context.handle(
          _internalNoteMeta,
          internalNote.isAcceptableOrUnknown(
              data['internal_note']!, _internalNoteMeta));
    }
    if (data.containsKey('struk_note')) {
      context.handle(_strukNoteMeta,
          strukNote.isAcceptableOrUnknown(data['struk_note']!, _strukNoteMeta));
    }
    if (data.containsKey('employee_name')) {
      context.handle(
          _employeeNameMeta,
          employeeName.isAcceptableOrUnknown(
              data['employee_name']!, _employeeNameMeta));
    }
    if (data.containsKey('points_earned')) {
      context.handle(
          _pointsEarnedMeta,
          pointsEarned.isAcceptableOrUnknown(
              data['points_earned']!, _pointsEarnedMeta));
    }
    if (data.containsKey('change_taken')) {
      context.handle(
          _changeTakenMeta,
          changeTaken.isAcceptableOrUnknown(
              data['change_taken']!, _changeTakenMeta));
    }
    if (data.containsKey('checked_item_ids')) {
      context.handle(
          _checkedItemIdsMeta,
          checkedItemIds.isAcceptableOrUnknown(
              data['checked_item_ids']!, _checkedItemIdsMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_id'])!,
      kasirId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kasir_id']),
      customerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}customer_id']),
      customerName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}customer_name']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      total: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total'])!,
      paid: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}paid'])!,
      changeAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}change_amount'])!,
      paymentMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_method'])!,
      internalNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}internal_note']),
      strukNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}struk_note']),
      employeeName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}employee_name']),
      pointsEarned: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}points_earned'])!,
      changeTaken: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}change_taken'])!,
      checkedItemIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}checked_item_ids']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final String id;
  final String localId;
  final String? kasirId;
  final String? customerId;

  /// Nama pembeli ad-hoc (bukan pelanggan terdaftar).
  /// customerId != null  -> pelanggan terdaftar (customerName diabaikan)
  /// customerName != null -> pembeli umum bernama, TIDAK masuk tabel customers
  /// keduanya null        -> ditampilkan sebagai "Umum"
  final String? customerName;
  final String status;
  final int total;
  final int paid;
  final int changeAmount;
  final String paymentMethod;
  final String? internalNote;
  final String? strukNote;

  /// Nama pegawai toko yang melayani / mengambilkan barang pada nota ini.
  /// Disimpan sebagai snapshot nama (denormalisasi) agar tetap akurat meski
  /// pegawai dihapus dari master. null = tidak diinput.
  final String? employeeName;
  final int pointsEarned;

  /// true bila kembalian sudah benar-benar diserahkan ke pembeli. Berguna
  /// untuk nota yang barangnya diambil belakangan — dicentang manual di
  /// struk agar kasir lain tidak memberikan kembalian dua kali. Murni
  /// per-perangkat (tidak ikut sync — sama seperti edit strukNote/
  /// internalNote setelah nota dibuat).
  final bool changeTaken;

  /// ID baris `transaction_items` yang sudah dicentang "diverifikasi/
  /// diserahkan" di struk in-app — JSON array of String. null/kosong =
  /// belum ada yang dicentang. Murni per-perangkat (tidak ikut sync — sama
  /// seperti `changeTaken`/`internalNote` setelah nota dibuat).
  final String? checkedItemIds;
  final DateTime createdAt;
  final DateTime? syncedAt;
  const Transaction(
      {required this.id,
      required this.localId,
      this.kasirId,
      this.customerId,
      this.customerName,
      required this.status,
      required this.total,
      required this.paid,
      required this.changeAmount,
      required this.paymentMethod,
      this.internalNote,
      this.strukNote,
      this.employeeName,
      required this.pointsEarned,
      required this.changeTaken,
      this.checkedItemIds,
      required this.createdAt,
      this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || kasirId != null) {
      map['kasir_id'] = Variable<String>(kasirId);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    if (!nullToAbsent || customerName != null) {
      map['customer_name'] = Variable<String>(customerName);
    }
    map['status'] = Variable<String>(status);
    map['total'] = Variable<int>(total);
    map['paid'] = Variable<int>(paid);
    map['change_amount'] = Variable<int>(changeAmount);
    map['payment_method'] = Variable<String>(paymentMethod);
    if (!nullToAbsent || internalNote != null) {
      map['internal_note'] = Variable<String>(internalNote);
    }
    if (!nullToAbsent || strukNote != null) {
      map['struk_note'] = Variable<String>(strukNote);
    }
    if (!nullToAbsent || employeeName != null) {
      map['employee_name'] = Variable<String>(employeeName);
    }
    map['points_earned'] = Variable<int>(pointsEarned);
    map['change_taken'] = Variable<bool>(changeTaken);
    if (!nullToAbsent || checkedItemIds != null) {
      map['checked_item_ids'] = Variable<String>(checkedItemIds);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      localId: Value(localId),
      kasirId: kasirId == null && nullToAbsent
          ? const Value.absent()
          : Value(kasirId),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      customerName: customerName == null && nullToAbsent
          ? const Value.absent()
          : Value(customerName),
      status: Value(status),
      total: Value(total),
      paid: Value(paid),
      changeAmount: Value(changeAmount),
      paymentMethod: Value(paymentMethod),
      internalNote: internalNote == null && nullToAbsent
          ? const Value.absent()
          : Value(internalNote),
      strukNote: strukNote == null && nullToAbsent
          ? const Value.absent()
          : Value(strukNote),
      employeeName: employeeName == null && nullToAbsent
          ? const Value.absent()
          : Value(employeeName),
      pointsEarned: Value(pointsEarned),
      changeTaken: Value(changeTaken),
      checkedItemIds: checkedItemIds == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedItemIds),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<String>(json['id']),
      localId: serializer.fromJson<String>(json['localId']),
      kasirId: serializer.fromJson<String?>(json['kasirId']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      customerName: serializer.fromJson<String?>(json['customerName']),
      status: serializer.fromJson<String>(json['status']),
      total: serializer.fromJson<int>(json['total']),
      paid: serializer.fromJson<int>(json['paid']),
      changeAmount: serializer.fromJson<int>(json['changeAmount']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      internalNote: serializer.fromJson<String?>(json['internalNote']),
      strukNote: serializer.fromJson<String?>(json['strukNote']),
      employeeName: serializer.fromJson<String?>(json['employeeName']),
      pointsEarned: serializer.fromJson<int>(json['pointsEarned']),
      changeTaken: serializer.fromJson<bool>(json['changeTaken']),
      checkedItemIds: serializer.fromJson<String?>(json['checkedItemIds']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'localId': serializer.toJson<String>(localId),
      'kasirId': serializer.toJson<String?>(kasirId),
      'customerId': serializer.toJson<String?>(customerId),
      'customerName': serializer.toJson<String?>(customerName),
      'status': serializer.toJson<String>(status),
      'total': serializer.toJson<int>(total),
      'paid': serializer.toJson<int>(paid),
      'changeAmount': serializer.toJson<int>(changeAmount),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'internalNote': serializer.toJson<String?>(internalNote),
      'strukNote': serializer.toJson<String?>(strukNote),
      'employeeName': serializer.toJson<String?>(employeeName),
      'pointsEarned': serializer.toJson<int>(pointsEarned),
      'changeTaken': serializer.toJson<bool>(changeTaken),
      'checkedItemIds': serializer.toJson<String?>(checkedItemIds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  Transaction copyWith(
          {String? id,
          String? localId,
          Value<String?> kasirId = const Value.absent(),
          Value<String?> customerId = const Value.absent(),
          Value<String?> customerName = const Value.absent(),
          String? status,
          int? total,
          int? paid,
          int? changeAmount,
          String? paymentMethod,
          Value<String?> internalNote = const Value.absent(),
          Value<String?> strukNote = const Value.absent(),
          Value<String?> employeeName = const Value.absent(),
          int? pointsEarned,
          bool? changeTaken,
          Value<String?> checkedItemIds = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> syncedAt = const Value.absent()}) =>
      Transaction(
        id: id ?? this.id,
        localId: localId ?? this.localId,
        kasirId: kasirId.present ? kasirId.value : this.kasirId,
        customerId: customerId.present ? customerId.value : this.customerId,
        customerName:
            customerName.present ? customerName.value : this.customerName,
        status: status ?? this.status,
        total: total ?? this.total,
        paid: paid ?? this.paid,
        changeAmount: changeAmount ?? this.changeAmount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        internalNote:
            internalNote.present ? internalNote.value : this.internalNote,
        strukNote: strukNote.present ? strukNote.value : this.strukNote,
        employeeName:
            employeeName.present ? employeeName.value : this.employeeName,
        pointsEarned: pointsEarned ?? this.pointsEarned,
        changeTaken: changeTaken ?? this.changeTaken,
        checkedItemIds:
            checkedItemIds.present ? checkedItemIds.value : this.checkedItemIds,
        createdAt: createdAt ?? this.createdAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      localId: data.localId.present ? data.localId.value : this.localId,
      kasirId: data.kasirId.present ? data.kasirId.value : this.kasirId,
      customerId:
          data.customerId.present ? data.customerId.value : this.customerId,
      customerName: data.customerName.present
          ? data.customerName.value
          : this.customerName,
      status: data.status.present ? data.status.value : this.status,
      total: data.total.present ? data.total.value : this.total,
      paid: data.paid.present ? data.paid.value : this.paid,
      changeAmount: data.changeAmount.present
          ? data.changeAmount.value
          : this.changeAmount,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      internalNote: data.internalNote.present
          ? data.internalNote.value
          : this.internalNote,
      strukNote: data.strukNote.present ? data.strukNote.value : this.strukNote,
      employeeName: data.employeeName.present
          ? data.employeeName.value
          : this.employeeName,
      pointsEarned: data.pointsEarned.present
          ? data.pointsEarned.value
          : this.pointsEarned,
      changeTaken:
          data.changeTaken.present ? data.changeTaken.value : this.changeTaken,
      checkedItemIds: data.checkedItemIds.present
          ? data.checkedItemIds.value
          : this.checkedItemIds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('kasirId: $kasirId, ')
          ..write('customerId: $customerId, ')
          ..write('customerName: $customerName, ')
          ..write('status: $status, ')
          ..write('total: $total, ')
          ..write('paid: $paid, ')
          ..write('changeAmount: $changeAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('internalNote: $internalNote, ')
          ..write('strukNote: $strukNote, ')
          ..write('employeeName: $employeeName, ')
          ..write('pointsEarned: $pointsEarned, ')
          ..write('changeTaken: $changeTaken, ')
          ..write('checkedItemIds: $checkedItemIds, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      localId,
      kasirId,
      customerId,
      customerName,
      status,
      total,
      paid,
      changeAmount,
      paymentMethod,
      internalNote,
      strukNote,
      employeeName,
      pointsEarned,
      changeTaken,
      checkedItemIds,
      createdAt,
      syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.localId == this.localId &&
          other.kasirId == this.kasirId &&
          other.customerId == this.customerId &&
          other.customerName == this.customerName &&
          other.status == this.status &&
          other.total == this.total &&
          other.paid == this.paid &&
          other.changeAmount == this.changeAmount &&
          other.paymentMethod == this.paymentMethod &&
          other.internalNote == this.internalNote &&
          other.strukNote == this.strukNote &&
          other.employeeName == this.employeeName &&
          other.pointsEarned == this.pointsEarned &&
          other.changeTaken == this.changeTaken &&
          other.checkedItemIds == this.checkedItemIds &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<String> id;
  final Value<String> localId;
  final Value<String?> kasirId;
  final Value<String?> customerId;
  final Value<String?> customerName;
  final Value<String> status;
  final Value<int> total;
  final Value<int> paid;
  final Value<int> changeAmount;
  final Value<String> paymentMethod;
  final Value<String?> internalNote;
  final Value<String?> strukNote;
  final Value<String?> employeeName;
  final Value<int> pointsEarned;
  final Value<bool> changeTaken;
  final Value<String?> checkedItemIds;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.localId = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.customerName = const Value.absent(),
    this.status = const Value.absent(),
    this.total = const Value.absent(),
    this.paid = const Value.absent(),
    this.changeAmount = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.internalNote = const Value.absent(),
    this.strukNote = const Value.absent(),
    this.employeeName = const Value.absent(),
    this.pointsEarned = const Value.absent(),
    this.changeTaken = const Value.absent(),
    this.checkedItemIds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String id,
    required String localId,
    this.kasirId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.customerName = const Value.absent(),
    required String status,
    required int total,
    required int paid,
    required int changeAmount,
    required String paymentMethod,
    this.internalNote = const Value.absent(),
    this.strukNote = const Value.absent(),
    this.employeeName = const Value.absent(),
    this.pointsEarned = const Value.absent(),
    this.changeTaken = const Value.absent(),
    this.checkedItemIds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        localId = Value(localId),
        status = Value(status),
        total = Value(total),
        paid = Value(paid),
        changeAmount = Value(changeAmount),
        paymentMethod = Value(paymentMethod);
  static Insertable<Transaction> custom({
    Expression<String>? id,
    Expression<String>? localId,
    Expression<String>? kasirId,
    Expression<String>? customerId,
    Expression<String>? customerName,
    Expression<String>? status,
    Expression<int>? total,
    Expression<int>? paid,
    Expression<int>? changeAmount,
    Expression<String>? paymentMethod,
    Expression<String>? internalNote,
    Expression<String>? strukNote,
    Expression<String>? employeeName,
    Expression<int>? pointsEarned,
    Expression<bool>? changeTaken,
    Expression<String>? checkedItemIds,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localId != null) 'local_id': localId,
      if (kasirId != null) 'kasir_id': kasirId,
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (status != null) 'status': status,
      if (total != null) 'total': total,
      if (paid != null) 'paid': paid,
      if (changeAmount != null) 'change_amount': changeAmount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (internalNote != null) 'internal_note': internalNote,
      if (strukNote != null) 'struk_note': strukNote,
      if (employeeName != null) 'employee_name': employeeName,
      if (pointsEarned != null) 'points_earned': pointsEarned,
      if (changeTaken != null) 'change_taken': changeTaken,
      if (checkedItemIds != null) 'checked_item_ids': checkedItemIds,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? localId,
      Value<String?>? kasirId,
      Value<String?>? customerId,
      Value<String?>? customerName,
      Value<String>? status,
      Value<int>? total,
      Value<int>? paid,
      Value<int>? changeAmount,
      Value<String>? paymentMethod,
      Value<String?>? internalNote,
      Value<String?>? strukNote,
      Value<String?>? employeeName,
      Value<int>? pointsEarned,
      Value<bool>? changeTaken,
      Value<String?>? checkedItemIds,
      Value<DateTime>? createdAt,
      Value<DateTime?>? syncedAt,
      Value<int>? rowid}) {
    return TransactionsCompanion(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      kasirId: kasirId ?? this.kasirId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      status: status ?? this.status,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      changeAmount: changeAmount ?? this.changeAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      internalNote: internalNote ?? this.internalNote,
      strukNote: strukNote ?? this.strukNote,
      employeeName: employeeName ?? this.employeeName,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      changeTaken: changeTaken ?? this.changeTaken,
      checkedItemIds: checkedItemIds ?? this.checkedItemIds,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (kasirId.present) {
      map['kasir_id'] = Variable<String>(kasirId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (total.present) {
      map['total'] = Variable<int>(total.value);
    }
    if (paid.present) {
      map['paid'] = Variable<int>(paid.value);
    }
    if (changeAmount.present) {
      map['change_amount'] = Variable<int>(changeAmount.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (internalNote.present) {
      map['internal_note'] = Variable<String>(internalNote.value);
    }
    if (strukNote.present) {
      map['struk_note'] = Variable<String>(strukNote.value);
    }
    if (employeeName.present) {
      map['employee_name'] = Variable<String>(employeeName.value);
    }
    if (pointsEarned.present) {
      map['points_earned'] = Variable<int>(pointsEarned.value);
    }
    if (changeTaken.present) {
      map['change_taken'] = Variable<bool>(changeTaken.value);
    }
    if (checkedItemIds.present) {
      map['checked_item_ids'] = Variable<String>(checkedItemIds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('kasirId: $kasirId, ')
          ..write('customerId: $customerId, ')
          ..write('customerName: $customerName, ')
          ..write('status: $status, ')
          ..write('total: $total, ')
          ..write('paid: $paid, ')
          ..write('changeAmount: $changeAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('internalNote: $internalNote, ')
          ..write('strukNote: $strukNote, ')
          ..write('employeeName: $employeeName, ')
          ..write('pointsEarned: $pointsEarned, ')
          ..write('changeTaken: $changeTaken, ')
          ..write('checkedItemIds: $checkedItemIds, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionItemsTable extends TransactionItems
    with TableInfo<$TransactionItemsTable, TransactionItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _transactionIdMeta =
      const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
      'transaction_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES transactions (id)'));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<double> qty = GeneratedColumn<double>(
      'qty', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _priceAtSaleMeta =
      const VerificationMeta('priceAtSale');
  @override
  late final GeneratedColumn<int> priceAtSale = GeneratedColumn<int>(
      'price_at_sale', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _originalPriceMeta =
      const VerificationMeta('originalPrice');
  @override
  late final GeneratedColumn<int> originalPrice = GeneratedColumn<int>(
      'original_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _priceOverriddenMeta =
      const VerificationMeta('priceOverridden');
  @override
  late final GeneratedColumn<bool> priceOverridden = GeneratedColumn<bool>(
      'price_overridden', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("price_overridden" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _costAtSaleMeta =
      const VerificationMeta('costAtSale');
  @override
  late final GeneratedColumn<int> costAtSale = GeneratedColumn<int>(
      'cost_at_sale', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _itemNoteMeta =
      const VerificationMeta('itemNote');
  @override
  late final GeneratedColumn<String> itemNote = GeneratedColumn<String>(
      'item_note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _subtotalMeta =
      const VerificationMeta('subtotal');
  @override
  late final GeneratedColumn<int> subtotal = GeneratedColumn<int>(
      'subtotal', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _returnedAtMeta =
      const VerificationMeta('returnedAt');
  @override
  late final GeneratedColumn<DateTime> returnedAt = GeneratedColumn<DateTime>(
      'returned_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        transactionId,
        productId,
        productUnitId,
        qty,
        priceAtSale,
        originalPrice,
        priceOverridden,
        costAtSale,
        itemNote,
        subtotal,
        addedAt,
        returnedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_items';
  @override
  VerificationContext validateIntegrity(Insertable<TransactionItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
          _transactionIdMeta,
          transactionId.isAcceptableOrUnknown(
              data['transaction_id']!, _transactionIdMeta));
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('qty')) {
      context.handle(
          _qtyMeta, qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta));
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('price_at_sale')) {
      context.handle(
          _priceAtSaleMeta,
          priceAtSale.isAcceptableOrUnknown(
              data['price_at_sale']!, _priceAtSaleMeta));
    } else if (isInserting) {
      context.missing(_priceAtSaleMeta);
    }
    if (data.containsKey('original_price')) {
      context.handle(
          _originalPriceMeta,
          originalPrice.isAcceptableOrUnknown(
              data['original_price']!, _originalPriceMeta));
    } else if (isInserting) {
      context.missing(_originalPriceMeta);
    }
    if (data.containsKey('price_overridden')) {
      context.handle(
          _priceOverriddenMeta,
          priceOverridden.isAcceptableOrUnknown(
              data['price_overridden']!, _priceOverriddenMeta));
    }
    if (data.containsKey('cost_at_sale')) {
      context.handle(
          _costAtSaleMeta,
          costAtSale.isAcceptableOrUnknown(
              data['cost_at_sale']!, _costAtSaleMeta));
    }
    if (data.containsKey('item_note')) {
      context.handle(_itemNoteMeta,
          itemNote.isAcceptableOrUnknown(data['item_note']!, _itemNoteMeta));
    }
    if (data.containsKey('subtotal')) {
      context.handle(_subtotalMeta,
          subtotal.isAcceptableOrUnknown(data['subtotal']!, _subtotalMeta));
    } else if (isInserting) {
      context.missing(_subtotalMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    if (data.containsKey('returned_at')) {
      context.handle(
          _returnedAtMeta,
          returnedAt.isAcceptableOrUnknown(
              data['returned_at']!, _returnedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      transactionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}transaction_id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      qty: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}qty'])!,
      priceAtSale: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price_at_sale'])!,
      originalPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}original_price'])!,
      priceOverridden: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}price_overridden'])!,
      costAtSale: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cost_at_sale'])!,
      itemNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_note']),
      subtotal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}subtotal'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at']),
      returnedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}returned_at']),
    );
  }

  @override
  $TransactionItemsTable createAlias(String alias) {
    return $TransactionItemsTable(attachedDatabase, alias);
  }
}

class TransactionItem extends DataClass implements Insertable<TransactionItem> {
  final String id;
  final String transactionId;
  final String productId;
  final String productUnitId;
  final double qty;
  final int priceAtSale;
  final int originalPrice;
  final bool priceOverridden;
  final int costAtSale;
  final String? itemNote;
  final int subtotal;

  /// Waktu item ditambahkan SETELAH transaksi awal selesai (fitur "tambah
  /// belanjaan"). null = item asli saat transaksi dibuat. Terisi = item susulan;
  /// dipakai struk in-app untuk memberi pembatas "Tambahan <jam>".
  final DateTime? addedAt;

  /// Item 49g — waktu baris retur INI dibuat (nota SUDAH LUNAS). null =
  /// baris penjualan biasa (baik asli maupun susulan). Terisi = baris retur
  /// (selalu `qty` NEGATIF, item ASLI yang diretur tidak pernah dihapus/
  /// diubah) — dipakai struk utk pembatas "Retur <jam>", pola sama dgn
  /// `addedAt`/"Tambahan".
  final DateTime? returnedAt;
  const TransactionItem(
      {required this.id,
      required this.transactionId,
      required this.productId,
      required this.productUnitId,
      required this.qty,
      required this.priceAtSale,
      required this.originalPrice,
      required this.priceOverridden,
      required this.costAtSale,
      this.itemNote,
      required this.subtotal,
      this.addedAt,
      this.returnedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['transaction_id'] = Variable<String>(transactionId);
    map['product_id'] = Variable<String>(productId);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['qty'] = Variable<double>(qty);
    map['price_at_sale'] = Variable<int>(priceAtSale);
    map['original_price'] = Variable<int>(originalPrice);
    map['price_overridden'] = Variable<bool>(priceOverridden);
    map['cost_at_sale'] = Variable<int>(costAtSale);
    if (!nullToAbsent || itemNote != null) {
      map['item_note'] = Variable<String>(itemNote);
    }
    map['subtotal'] = Variable<int>(subtotal);
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<DateTime>(addedAt);
    }
    if (!nullToAbsent || returnedAt != null) {
      map['returned_at'] = Variable<DateTime>(returnedAt);
    }
    return map;
  }

  TransactionItemsCompanion toCompanion(bool nullToAbsent) {
    return TransactionItemsCompanion(
      id: Value(id),
      transactionId: Value(transactionId),
      productId: Value(productId),
      productUnitId: Value(productUnitId),
      qty: Value(qty),
      priceAtSale: Value(priceAtSale),
      originalPrice: Value(originalPrice),
      priceOverridden: Value(priceOverridden),
      costAtSale: Value(costAtSale),
      itemNote: itemNote == null && nullToAbsent
          ? const Value.absent()
          : Value(itemNote),
      subtotal: Value(subtotal),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      returnedAt: returnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(returnedAt),
    );
  }

  factory TransactionItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionItem(
      id: serializer.fromJson<String>(json['id']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      productId: serializer.fromJson<String>(json['productId']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      qty: serializer.fromJson<double>(json['qty']),
      priceAtSale: serializer.fromJson<int>(json['priceAtSale']),
      originalPrice: serializer.fromJson<int>(json['originalPrice']),
      priceOverridden: serializer.fromJson<bool>(json['priceOverridden']),
      costAtSale: serializer.fromJson<int>(json['costAtSale']),
      itemNote: serializer.fromJson<String?>(json['itemNote']),
      subtotal: serializer.fromJson<int>(json['subtotal']),
      addedAt: serializer.fromJson<DateTime?>(json['addedAt']),
      returnedAt: serializer.fromJson<DateTime?>(json['returnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'transactionId': serializer.toJson<String>(transactionId),
      'productId': serializer.toJson<String>(productId),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'qty': serializer.toJson<double>(qty),
      'priceAtSale': serializer.toJson<int>(priceAtSale),
      'originalPrice': serializer.toJson<int>(originalPrice),
      'priceOverridden': serializer.toJson<bool>(priceOverridden),
      'costAtSale': serializer.toJson<int>(costAtSale),
      'itemNote': serializer.toJson<String?>(itemNote),
      'subtotal': serializer.toJson<int>(subtotal),
      'addedAt': serializer.toJson<DateTime?>(addedAt),
      'returnedAt': serializer.toJson<DateTime?>(returnedAt),
    };
  }

  TransactionItem copyWith(
          {String? id,
          String? transactionId,
          String? productId,
          String? productUnitId,
          double? qty,
          int? priceAtSale,
          int? originalPrice,
          bool? priceOverridden,
          int? costAtSale,
          Value<String?> itemNote = const Value.absent(),
          int? subtotal,
          Value<DateTime?> addedAt = const Value.absent(),
          Value<DateTime?> returnedAt = const Value.absent()}) =>
      TransactionItem(
        id: id ?? this.id,
        transactionId: transactionId ?? this.transactionId,
        productId: productId ?? this.productId,
        productUnitId: productUnitId ?? this.productUnitId,
        qty: qty ?? this.qty,
        priceAtSale: priceAtSale ?? this.priceAtSale,
        originalPrice: originalPrice ?? this.originalPrice,
        priceOverridden: priceOverridden ?? this.priceOverridden,
        costAtSale: costAtSale ?? this.costAtSale,
        itemNote: itemNote.present ? itemNote.value : this.itemNote,
        subtotal: subtotal ?? this.subtotal,
        addedAt: addedAt.present ? addedAt.value : this.addedAt,
        returnedAt: returnedAt.present ? returnedAt.value : this.returnedAt,
      );
  TransactionItem copyWithCompanion(TransactionItemsCompanion data) {
    return TransactionItem(
      id: data.id.present ? data.id.value : this.id,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      productId: data.productId.present ? data.productId.value : this.productId,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      qty: data.qty.present ? data.qty.value : this.qty,
      priceAtSale:
          data.priceAtSale.present ? data.priceAtSale.value : this.priceAtSale,
      originalPrice: data.originalPrice.present
          ? data.originalPrice.value
          : this.originalPrice,
      priceOverridden: data.priceOverridden.present
          ? data.priceOverridden.value
          : this.priceOverridden,
      costAtSale:
          data.costAtSale.present ? data.costAtSale.value : this.costAtSale,
      itemNote: data.itemNote.present ? data.itemNote.value : this.itemNote,
      subtotal: data.subtotal.present ? data.subtotal.value : this.subtotal,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      returnedAt:
          data.returnedAt.present ? data.returnedAt.value : this.returnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionItem(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('productId: $productId, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('qty: $qty, ')
          ..write('priceAtSale: $priceAtSale, ')
          ..write('originalPrice: $originalPrice, ')
          ..write('priceOverridden: $priceOverridden, ')
          ..write('costAtSale: $costAtSale, ')
          ..write('itemNote: $itemNote, ')
          ..write('subtotal: $subtotal, ')
          ..write('addedAt: $addedAt, ')
          ..write('returnedAt: $returnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      transactionId,
      productId,
      productUnitId,
      qty,
      priceAtSale,
      originalPrice,
      priceOverridden,
      costAtSale,
      itemNote,
      subtotal,
      addedAt,
      returnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionItem &&
          other.id == this.id &&
          other.transactionId == this.transactionId &&
          other.productId == this.productId &&
          other.productUnitId == this.productUnitId &&
          other.qty == this.qty &&
          other.priceAtSale == this.priceAtSale &&
          other.originalPrice == this.originalPrice &&
          other.priceOverridden == this.priceOverridden &&
          other.costAtSale == this.costAtSale &&
          other.itemNote == this.itemNote &&
          other.subtotal == this.subtotal &&
          other.addedAt == this.addedAt &&
          other.returnedAt == this.returnedAt);
}

class TransactionItemsCompanion extends UpdateCompanion<TransactionItem> {
  final Value<String> id;
  final Value<String> transactionId;
  final Value<String> productId;
  final Value<String> productUnitId;
  final Value<double> qty;
  final Value<int> priceAtSale;
  final Value<int> originalPrice;
  final Value<bool> priceOverridden;
  final Value<int> costAtSale;
  final Value<String?> itemNote;
  final Value<int> subtotal;
  final Value<DateTime?> addedAt;
  final Value<DateTime?> returnedAt;
  final Value<int> rowid;
  const TransactionItemsCompanion({
    this.id = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.productId = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.qty = const Value.absent(),
    this.priceAtSale = const Value.absent(),
    this.originalPrice = const Value.absent(),
    this.priceOverridden = const Value.absent(),
    this.costAtSale = const Value.absent(),
    this.itemNote = const Value.absent(),
    this.subtotal = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.returnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionItemsCompanion.insert({
    required String id,
    required String transactionId,
    required String productId,
    required String productUnitId,
    required double qty,
    required int priceAtSale,
    required int originalPrice,
    this.priceOverridden = const Value.absent(),
    this.costAtSale = const Value.absent(),
    this.itemNote = const Value.absent(),
    required int subtotal,
    this.addedAt = const Value.absent(),
    this.returnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        transactionId = Value(transactionId),
        productId = Value(productId),
        productUnitId = Value(productUnitId),
        qty = Value(qty),
        priceAtSale = Value(priceAtSale),
        originalPrice = Value(originalPrice),
        subtotal = Value(subtotal);
  static Insertable<TransactionItem> custom({
    Expression<String>? id,
    Expression<String>? transactionId,
    Expression<String>? productId,
    Expression<String>? productUnitId,
    Expression<double>? qty,
    Expression<int>? priceAtSale,
    Expression<int>? originalPrice,
    Expression<bool>? priceOverridden,
    Expression<int>? costAtSale,
    Expression<String>? itemNote,
    Expression<int>? subtotal,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? returnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (productId != null) 'product_id': productId,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (qty != null) 'qty': qty,
      if (priceAtSale != null) 'price_at_sale': priceAtSale,
      if (originalPrice != null) 'original_price': originalPrice,
      if (priceOverridden != null) 'price_overridden': priceOverridden,
      if (costAtSale != null) 'cost_at_sale': costAtSale,
      if (itemNote != null) 'item_note': itemNote,
      if (subtotal != null) 'subtotal': subtotal,
      if (addedAt != null) 'added_at': addedAt,
      if (returnedAt != null) 'returned_at': returnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? transactionId,
      Value<String>? productId,
      Value<String>? productUnitId,
      Value<double>? qty,
      Value<int>? priceAtSale,
      Value<int>? originalPrice,
      Value<bool>? priceOverridden,
      Value<int>? costAtSale,
      Value<String?>? itemNote,
      Value<int>? subtotal,
      Value<DateTime?>? addedAt,
      Value<DateTime?>? returnedAt,
      Value<int>? rowid}) {
    return TransactionItemsCompanion(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      productId: productId ?? this.productId,
      productUnitId: productUnitId ?? this.productUnitId,
      qty: qty ?? this.qty,
      priceAtSale: priceAtSale ?? this.priceAtSale,
      originalPrice: originalPrice ?? this.originalPrice,
      priceOverridden: priceOverridden ?? this.priceOverridden,
      costAtSale: costAtSale ?? this.costAtSale,
      itemNote: itemNote ?? this.itemNote,
      subtotal: subtotal ?? this.subtotal,
      addedAt: addedAt ?? this.addedAt,
      returnedAt: returnedAt ?? this.returnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<double>(qty.value);
    }
    if (priceAtSale.present) {
      map['price_at_sale'] = Variable<int>(priceAtSale.value);
    }
    if (originalPrice.present) {
      map['original_price'] = Variable<int>(originalPrice.value);
    }
    if (priceOverridden.present) {
      map['price_overridden'] = Variable<bool>(priceOverridden.value);
    }
    if (costAtSale.present) {
      map['cost_at_sale'] = Variable<int>(costAtSale.value);
    }
    if (itemNote.present) {
      map['item_note'] = Variable<String>(itemNote.value);
    }
    if (subtotal.present) {
      map['subtotal'] = Variable<int>(subtotal.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (returnedAt.present) {
      map['returned_at'] = Variable<DateTime>(returnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionItemsCompanion(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('productId: $productId, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('qty: $qty, ')
          ..write('priceAtSale: $priceAtSale, ')
          ..write('originalPrice: $originalPrice, ')
          ..write('priceOverridden: $priceOverridden, ')
          ..write('costAtSale: $costAtSale, ')
          ..write('itemNote: $itemNote, ')
          ..write('subtotal: $subtotal, ')
          ..write('addedAt: $addedAt, ')
          ..write('returnedAt: $returnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionPaymentsTable extends TransactionPayments
    with TableInfo<$TransactionPaymentsTable, TransactionPayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _transactionIdMeta =
      const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
      'transaction_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES transactions (id)'));
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
      'amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
      'method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _paidAtMeta = const VerificationMeta('paidAt');
  @override
  late final GeneratedColumn<DateTime> paidAt = GeneratedColumn<DateTime>(
      'paid_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _kasirIdMeta =
      const VerificationMeta('kasirId');
  @override
  late final GeneratedColumn<String> kasirId = GeneratedColumn<String>(
      'kasir_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _changeGivenMeta =
      const VerificationMeta('changeGiven');
  @override
  late final GeneratedColumn<int> changeGiven = GeneratedColumn<int>(
      'change_given', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _changeTakenMeta =
      const VerificationMeta('changeTaken');
  @override
  late final GeneratedColumn<bool> changeTaken = GeneratedColumn<bool>(
      'change_taken', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("change_taken" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _voidedMeta = const VerificationMeta('voided');
  @override
  late final GeneratedColumn<bool> voided = GeneratedColumn<bool>(
      'voided', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("voided" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        transactionId,
        amount,
        method,
        paidAt,
        kasirId,
        note,
        changeGiven,
        changeTaken,
        voided
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_payments';
  @override
  VerificationContext validateIntegrity(Insertable<TransactionPayment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
          _transactionIdMeta,
          transactionId.isAcceptableOrUnknown(
              data['transaction_id']!, _transactionIdMeta));
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('method')) {
      context.handle(_methodMeta,
          method.isAcceptableOrUnknown(data['method']!, _methodMeta));
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('paid_at')) {
      context.handle(_paidAtMeta,
          paidAt.isAcceptableOrUnknown(data['paid_at']!, _paidAtMeta));
    }
    if (data.containsKey('kasir_id')) {
      context.handle(_kasirIdMeta,
          kasirId.isAcceptableOrUnknown(data['kasir_id']!, _kasirIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('change_given')) {
      context.handle(
          _changeGivenMeta,
          changeGiven.isAcceptableOrUnknown(
              data['change_given']!, _changeGivenMeta));
    }
    if (data.containsKey('change_taken')) {
      context.handle(
          _changeTakenMeta,
          changeTaken.isAcceptableOrUnknown(
              data['change_taken']!, _changeTakenMeta));
    }
    if (data.containsKey('voided')) {
      context.handle(_voidedMeta,
          voided.isAcceptableOrUnknown(data['voided']!, _voidedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionPayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionPayment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      transactionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}transaction_id'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount'])!,
      method: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}method'])!,
      paidAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}paid_at'])!,
      kasirId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kasir_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      changeGiven: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}change_given'])!,
      changeTaken: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}change_taken'])!,
      voided: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}voided'])!,
    );
  }

  @override
  $TransactionPaymentsTable createAlias(String alias) {
    return $TransactionPaymentsTable(attachedDatabase, alias);
  }
}

class TransactionPayment extends DataClass
    implements Insertable<TransactionPayment> {
  final String id;
  final String transactionId;
  final int amount;
  final String method;
  final DateTime paidAt;
  final String? kasirId;
  final String? note;

  /// Kembalian yang dihasilkan OLEH pembayaran ini secara spesifik (bukan
  /// akumulatif transaksi) — dihitung & disimpan SEKALI saat baris ini
  /// dibuat (lihat `AppDatabase._computePaymentChangeGiven`). Immutable
  /// setelahnya: fakta historis "saat itu kembaliannya segini" tidak boleh
  /// berubah walau total transaksi berubah belakangan (mis. tambah
  /// belanjaan) — beda dari `Transactions.changeAmount` yang selalu
  /// dihitung ulang dari kondisi TERKINI.
  final int changeGiven;

  /// true bila kembalian baris pembayaran INI sudah diserahkan ke pembeli.
  /// Per-pembayaran (bukan per-transaksi) — nota dengan beberapa pembayaran
  /// (tambah bayar/tambah belanjaan) bisa punya beberapa kembalian terpisah,
  /// masing-masing dengan status ambil sendiri-sendiri. Murni per-perangkat
  /// (tidak ikut sync — sama seperti `Transactions.changeTaken`).
  final bool changeTaken;

  /// true bila pembayaran ini DIBATALKAN (fitur "Batalkan Pembayaran") —
  /// baris TETAP tersimpan sbg jejak audit (kapan pernah dibayar, lalu
  /// dibatalkan), tapi TIDAK ikut dihitung ke `Transactions.paid`/status
  /// nota. Beda dari void transaksi (`Transactions.status = 'void'`, yang
  /// membatalkan SELURUH nota + stok + poin) — ini murni membatalkan SATU
  /// baris pembayaran, item & stok tidak tersentuh.
  final bool voided;
  const TransactionPayment(
      {required this.id,
      required this.transactionId,
      required this.amount,
      required this.method,
      required this.paidAt,
      this.kasirId,
      this.note,
      required this.changeGiven,
      required this.changeTaken,
      required this.voided});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['transaction_id'] = Variable<String>(transactionId);
    map['amount'] = Variable<int>(amount);
    map['method'] = Variable<String>(method);
    map['paid_at'] = Variable<DateTime>(paidAt);
    if (!nullToAbsent || kasirId != null) {
      map['kasir_id'] = Variable<String>(kasirId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['change_given'] = Variable<int>(changeGiven);
    map['change_taken'] = Variable<bool>(changeTaken);
    map['voided'] = Variable<bool>(voided);
    return map;
  }

  TransactionPaymentsCompanion toCompanion(bool nullToAbsent) {
    return TransactionPaymentsCompanion(
      id: Value(id),
      transactionId: Value(transactionId),
      amount: Value(amount),
      method: Value(method),
      paidAt: Value(paidAt),
      kasirId: kasirId == null && nullToAbsent
          ? const Value.absent()
          : Value(kasirId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      changeGiven: Value(changeGiven),
      changeTaken: Value(changeTaken),
      voided: Value(voided),
    );
  }

  factory TransactionPayment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionPayment(
      id: serializer.fromJson<String>(json['id']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      amount: serializer.fromJson<int>(json['amount']),
      method: serializer.fromJson<String>(json['method']),
      paidAt: serializer.fromJson<DateTime>(json['paidAt']),
      kasirId: serializer.fromJson<String?>(json['kasirId']),
      note: serializer.fromJson<String?>(json['note']),
      changeGiven: serializer.fromJson<int>(json['changeGiven']),
      changeTaken: serializer.fromJson<bool>(json['changeTaken']),
      voided: serializer.fromJson<bool>(json['voided']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'transactionId': serializer.toJson<String>(transactionId),
      'amount': serializer.toJson<int>(amount),
      'method': serializer.toJson<String>(method),
      'paidAt': serializer.toJson<DateTime>(paidAt),
      'kasirId': serializer.toJson<String?>(kasirId),
      'note': serializer.toJson<String?>(note),
      'changeGiven': serializer.toJson<int>(changeGiven),
      'changeTaken': serializer.toJson<bool>(changeTaken),
      'voided': serializer.toJson<bool>(voided),
    };
  }

  TransactionPayment copyWith(
          {String? id,
          String? transactionId,
          int? amount,
          String? method,
          DateTime? paidAt,
          Value<String?> kasirId = const Value.absent(),
          Value<String?> note = const Value.absent(),
          int? changeGiven,
          bool? changeTaken,
          bool? voided}) =>
      TransactionPayment(
        id: id ?? this.id,
        transactionId: transactionId ?? this.transactionId,
        amount: amount ?? this.amount,
        method: method ?? this.method,
        paidAt: paidAt ?? this.paidAt,
        kasirId: kasirId.present ? kasirId.value : this.kasirId,
        note: note.present ? note.value : this.note,
        changeGiven: changeGiven ?? this.changeGiven,
        changeTaken: changeTaken ?? this.changeTaken,
        voided: voided ?? this.voided,
      );
  TransactionPayment copyWithCompanion(TransactionPaymentsCompanion data) {
    return TransactionPayment(
      id: data.id.present ? data.id.value : this.id,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      amount: data.amount.present ? data.amount.value : this.amount,
      method: data.method.present ? data.method.value : this.method,
      paidAt: data.paidAt.present ? data.paidAt.value : this.paidAt,
      kasirId: data.kasirId.present ? data.kasirId.value : this.kasirId,
      note: data.note.present ? data.note.value : this.note,
      changeGiven:
          data.changeGiven.present ? data.changeGiven.value : this.changeGiven,
      changeTaken:
          data.changeTaken.present ? data.changeTaken.value : this.changeTaken,
      voided: data.voided.present ? data.voided.value : this.voided,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionPayment(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('amount: $amount, ')
          ..write('method: $method, ')
          ..write('paidAt: $paidAt, ')
          ..write('kasirId: $kasirId, ')
          ..write('note: $note, ')
          ..write('changeGiven: $changeGiven, ')
          ..write('changeTaken: $changeTaken, ')
          ..write('voided: $voided')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, transactionId, amount, method, paidAt,
      kasirId, note, changeGiven, changeTaken, voided);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionPayment &&
          other.id == this.id &&
          other.transactionId == this.transactionId &&
          other.amount == this.amount &&
          other.method == this.method &&
          other.paidAt == this.paidAt &&
          other.kasirId == this.kasirId &&
          other.note == this.note &&
          other.changeGiven == this.changeGiven &&
          other.changeTaken == this.changeTaken &&
          other.voided == this.voided);
}

class TransactionPaymentsCompanion extends UpdateCompanion<TransactionPayment> {
  final Value<String> id;
  final Value<String> transactionId;
  final Value<int> amount;
  final Value<String> method;
  final Value<DateTime> paidAt;
  final Value<String?> kasirId;
  final Value<String?> note;
  final Value<int> changeGiven;
  final Value<bool> changeTaken;
  final Value<bool> voided;
  final Value<int> rowid;
  const TransactionPaymentsCompanion({
    this.id = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.amount = const Value.absent(),
    this.method = const Value.absent(),
    this.paidAt = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.note = const Value.absent(),
    this.changeGiven = const Value.absent(),
    this.changeTaken = const Value.absent(),
    this.voided = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionPaymentsCompanion.insert({
    required String id,
    required String transactionId,
    required int amount,
    required String method,
    this.paidAt = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.note = const Value.absent(),
    this.changeGiven = const Value.absent(),
    this.changeTaken = const Value.absent(),
    this.voided = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        transactionId = Value(transactionId),
        amount = Value(amount),
        method = Value(method);
  static Insertable<TransactionPayment> custom({
    Expression<String>? id,
    Expression<String>? transactionId,
    Expression<int>? amount,
    Expression<String>? method,
    Expression<DateTime>? paidAt,
    Expression<String>? kasirId,
    Expression<String>? note,
    Expression<int>? changeGiven,
    Expression<bool>? changeTaken,
    Expression<bool>? voided,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (amount != null) 'amount': amount,
      if (method != null) 'method': method,
      if (paidAt != null) 'paid_at': paidAt,
      if (kasirId != null) 'kasir_id': kasirId,
      if (note != null) 'note': note,
      if (changeGiven != null) 'change_given': changeGiven,
      if (changeTaken != null) 'change_taken': changeTaken,
      if (voided != null) 'voided': voided,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionPaymentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? transactionId,
      Value<int>? amount,
      Value<String>? method,
      Value<DateTime>? paidAt,
      Value<String?>? kasirId,
      Value<String?>? note,
      Value<int>? changeGiven,
      Value<bool>? changeTaken,
      Value<bool>? voided,
      Value<int>? rowid}) {
    return TransactionPaymentsCompanion(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      paidAt: paidAt ?? this.paidAt,
      kasirId: kasirId ?? this.kasirId,
      note: note ?? this.note,
      changeGiven: changeGiven ?? this.changeGiven,
      changeTaken: changeTaken ?? this.changeTaken,
      voided: voided ?? this.voided,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (paidAt.present) {
      map['paid_at'] = Variable<DateTime>(paidAt.value);
    }
    if (kasirId.present) {
      map['kasir_id'] = Variable<String>(kasirId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (changeGiven.present) {
      map['change_given'] = Variable<int>(changeGiven.value);
    }
    if (changeTaken.present) {
      map['change_taken'] = Variable<bool>(changeTaken.value);
    }
    if (voided.present) {
      map['voided'] = Variable<bool>(voided.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionPaymentsCompanion(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('amount: $amount, ')
          ..write('method: $method, ')
          ..write('paidAt: $paidAt, ')
          ..write('kasirId: $kasirId, ')
          ..write('note: $note, ')
          ..write('changeGiven: $changeGiven, ')
          ..write('changeTaken: $changeTaken, ')
          ..write('voided: $voided, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HeldOrdersTable extends HeldOrders
    with TableInfo<$HeldOrdersTable, HeldOrder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HeldOrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cartJsonMeta =
      const VerificationMeta('cartJson');
  @override
  late final GeneratedColumn<String> cartJson = GeneratedColumn<String>(
      'cart_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, label, cartJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'held_orders';
  @override
  VerificationContext validateIntegrity(Insertable<HeldOrder> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('cart_json')) {
      context.handle(_cartJsonMeta,
          cartJson.isAcceptableOrUnknown(data['cart_json']!, _cartJsonMeta));
    } else if (isInserting) {
      context.missing(_cartJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HeldOrder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HeldOrder(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      cartJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cart_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $HeldOrdersTable createAlias(String alias) {
    return $HeldOrdersTable(attachedDatabase, alias);
  }
}

class HeldOrder extends DataClass implements Insertable<HeldOrder> {
  final String id;
  final String label;
  final String cartJson;
  final DateTime createdAt;
  const HeldOrder(
      {required this.id,
      required this.label,
      required this.cartJson,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    map['cart_json'] = Variable<String>(cartJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  HeldOrdersCompanion toCompanion(bool nullToAbsent) {
    return HeldOrdersCompanion(
      id: Value(id),
      label: Value(label),
      cartJson: Value(cartJson),
      createdAt: Value(createdAt),
    );
  }

  factory HeldOrder.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HeldOrder(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      cartJson: serializer.fromJson<String>(json['cartJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'cartJson': serializer.toJson<String>(cartJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  HeldOrder copyWith(
          {String? id, String? label, String? cartJson, DateTime? createdAt}) =>
      HeldOrder(
        id: id ?? this.id,
        label: label ?? this.label,
        cartJson: cartJson ?? this.cartJson,
        createdAt: createdAt ?? this.createdAt,
      );
  HeldOrder copyWithCompanion(HeldOrdersCompanion data) {
    return HeldOrder(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      cartJson: data.cartJson.present ? data.cartJson.value : this.cartJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HeldOrder(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('cartJson: $cartJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, label, cartJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HeldOrder &&
          other.id == this.id &&
          other.label == this.label &&
          other.cartJson == this.cartJson &&
          other.createdAt == this.createdAt);
}

class HeldOrdersCompanion extends UpdateCompanion<HeldOrder> {
  final Value<String> id;
  final Value<String> label;
  final Value<String> cartJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const HeldOrdersCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.cartJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HeldOrdersCompanion.insert({
    required String id,
    required String label,
    required String cartJson,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        label = Value(label),
        cartJson = Value(cartJson);
  static Insertable<HeldOrder> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<String>? cartJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (cartJson != null) 'cart_json': cartJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HeldOrdersCompanion copyWith(
      {Value<String>? id,
      Value<String>? label,
      Value<String>? cartJson,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return HeldOrdersCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      cartJson: cartJson ?? this.cartJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (cartJson.present) {
      map['cart_json'] = Variable<String>(cartJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HeldOrdersCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('cartJson: $cartJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockLedgerTable extends StockLedger
    with TableInfo<$StockLedgerTable, StockLedgerData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockLedgerTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _qtyChangeMeta =
      const VerificationMeta('qtyChange');
  @override
  late final GeneratedColumn<double> qtyChange = GeneratedColumn<double>(
      'qty_change', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _stockAfterMeta =
      const VerificationMeta('stockAfter');
  @override
  late final GeneratedColumn<double> stockAfter = GeneratedColumn<double>(
      'stock_after', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
      'reference_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _kasirIdMeta =
      const VerificationMeta('kasirId');
  @override
  late final GeneratedColumn<String> kasirId = GeneratedColumn<String>(
      'kasir_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productUnitId,
        type,
        qtyChange,
        stockAfter,
        referenceId,
        kasirId,
        note,
        createdAt,
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_ledger';
  @override
  VerificationContext validateIntegrity(Insertable<StockLedgerData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('qty_change')) {
      context.handle(_qtyChangeMeta,
          qtyChange.isAcceptableOrUnknown(data['qty_change']!, _qtyChangeMeta));
    } else if (isInserting) {
      context.missing(_qtyChangeMeta);
    }
    if (data.containsKey('stock_after')) {
      context.handle(
          _stockAfterMeta,
          stockAfter.isAcceptableOrUnknown(
              data['stock_after']!, _stockAfterMeta));
    } else if (isInserting) {
      context.missing(_stockAfterMeta);
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    }
    if (data.containsKey('kasir_id')) {
      context.handle(_kasirIdMeta,
          kasirId.isAcceptableOrUnknown(data['kasir_id']!, _kasirIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockLedgerData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockLedgerData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      qtyChange: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}qty_change'])!,
      stockAfter: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}stock_after'])!,
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_id']),
      kasirId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kasir_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $StockLedgerTable createAlias(String alias) {
    return $StockLedgerTable(attachedDatabase, alias);
  }
}

class StockLedgerData extends DataClass implements Insertable<StockLedgerData> {
  final String id;
  final String productUnitId;
  final String type;
  final double qtyChange;
  final double stockAfter;
  final String? referenceId;
  final String? kasirId;
  final String? note;
  final DateTime createdAt;
  final DateTime? syncedAt;
  const StockLedgerData(
      {required this.id,
      required this.productUnitId,
      required this.type,
      required this.qtyChange,
      required this.stockAfter,
      this.referenceId,
      this.kasirId,
      this.note,
      required this.createdAt,
      this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['type'] = Variable<String>(type);
    map['qty_change'] = Variable<double>(qtyChange);
    map['stock_after'] = Variable<double>(stockAfter);
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    if (!nullToAbsent || kasirId != null) {
      map['kasir_id'] = Variable<String>(kasirId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  StockLedgerCompanion toCompanion(bool nullToAbsent) {
    return StockLedgerCompanion(
      id: Value(id),
      productUnitId: Value(productUnitId),
      type: Value(type),
      qtyChange: Value(qtyChange),
      stockAfter: Value(stockAfter),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      kasirId: kasirId == null && nullToAbsent
          ? const Value.absent()
          : Value(kasirId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory StockLedgerData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockLedgerData(
      id: serializer.fromJson<String>(json['id']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      type: serializer.fromJson<String>(json['type']),
      qtyChange: serializer.fromJson<double>(json['qtyChange']),
      stockAfter: serializer.fromJson<double>(json['stockAfter']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      kasirId: serializer.fromJson<String?>(json['kasirId']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'type': serializer.toJson<String>(type),
      'qtyChange': serializer.toJson<double>(qtyChange),
      'stockAfter': serializer.toJson<double>(stockAfter),
      'referenceId': serializer.toJson<String?>(referenceId),
      'kasirId': serializer.toJson<String?>(kasirId),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  StockLedgerData copyWith(
          {String? id,
          String? productUnitId,
          String? type,
          double? qtyChange,
          double? stockAfter,
          Value<String?> referenceId = const Value.absent(),
          Value<String?> kasirId = const Value.absent(),
          Value<String?> note = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> syncedAt = const Value.absent()}) =>
      StockLedgerData(
        id: id ?? this.id,
        productUnitId: productUnitId ?? this.productUnitId,
        type: type ?? this.type,
        qtyChange: qtyChange ?? this.qtyChange,
        stockAfter: stockAfter ?? this.stockAfter,
        referenceId: referenceId.present ? referenceId.value : this.referenceId,
        kasirId: kasirId.present ? kasirId.value : this.kasirId,
        note: note.present ? note.value : this.note,
        createdAt: createdAt ?? this.createdAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );
  StockLedgerData copyWithCompanion(StockLedgerCompanion data) {
    return StockLedgerData(
      id: data.id.present ? data.id.value : this.id,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      type: data.type.present ? data.type.value : this.type,
      qtyChange: data.qtyChange.present ? data.qtyChange.value : this.qtyChange,
      stockAfter:
          data.stockAfter.present ? data.stockAfter.value : this.stockAfter,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      kasirId: data.kasirId.present ? data.kasirId.value : this.kasirId,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockLedgerData(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('type: $type, ')
          ..write('qtyChange: $qtyChange, ')
          ..write('stockAfter: $stockAfter, ')
          ..write('referenceId: $referenceId, ')
          ..write('kasirId: $kasirId, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productUnitId, type, qtyChange,
      stockAfter, referenceId, kasirId, note, createdAt, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockLedgerData &&
          other.id == this.id &&
          other.productUnitId == this.productUnitId &&
          other.type == this.type &&
          other.qtyChange == this.qtyChange &&
          other.stockAfter == this.stockAfter &&
          other.referenceId == this.referenceId &&
          other.kasirId == this.kasirId &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt);
}

class StockLedgerCompanion extends UpdateCompanion<StockLedgerData> {
  final Value<String> id;
  final Value<String> productUnitId;
  final Value<String> type;
  final Value<double> qtyChange;
  final Value<double> stockAfter;
  final Value<String?> referenceId;
  final Value<String?> kasirId;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const StockLedgerCompanion({
    this.id = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.type = const Value.absent(),
    this.qtyChange = const Value.absent(),
    this.stockAfter = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockLedgerCompanion.insert({
    required String id,
    required String productUnitId,
    required String type,
    required double qtyChange,
    required double stockAfter,
    this.referenceId = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productUnitId = Value(productUnitId),
        type = Value(type),
        qtyChange = Value(qtyChange),
        stockAfter = Value(stockAfter);
  static Insertable<StockLedgerData> custom({
    Expression<String>? id,
    Expression<String>? productUnitId,
    Expression<String>? type,
    Expression<double>? qtyChange,
    Expression<double>? stockAfter,
    Expression<String>? referenceId,
    Expression<String>? kasirId,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (type != null) 'type': type,
      if (qtyChange != null) 'qty_change': qtyChange,
      if (stockAfter != null) 'stock_after': stockAfter,
      if (referenceId != null) 'reference_id': referenceId,
      if (kasirId != null) 'kasir_id': kasirId,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockLedgerCompanion copyWith(
      {Value<String>? id,
      Value<String>? productUnitId,
      Value<String>? type,
      Value<double>? qtyChange,
      Value<double>? stockAfter,
      Value<String?>? referenceId,
      Value<String?>? kasirId,
      Value<String?>? note,
      Value<DateTime>? createdAt,
      Value<DateTime?>? syncedAt,
      Value<int>? rowid}) {
    return StockLedgerCompanion(
      id: id ?? this.id,
      productUnitId: productUnitId ?? this.productUnitId,
      type: type ?? this.type,
      qtyChange: qtyChange ?? this.qtyChange,
      stockAfter: stockAfter ?? this.stockAfter,
      referenceId: referenceId ?? this.referenceId,
      kasirId: kasirId ?? this.kasirId,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (qtyChange.present) {
      map['qty_change'] = Variable<double>(qtyChange.value);
    }
    if (stockAfter.present) {
      map['stock_after'] = Variable<double>(stockAfter.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (kasirId.present) {
      map['kasir_id'] = Variable<String>(kasirId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockLedgerCompanion(')
          ..write('id: $id, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('type: $type, ')
          ..write('qtyChange: $qtyChange, ')
          ..write('stockAfter: $stockAfter, ')
          ..write('referenceId: $referenceId, ')
          ..write('kasirId: $kasirId, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpensesTable extends Expenses with TableInfo<$ExpensesTable, Expense> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
      'local_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
      'amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
      'reference_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _kasirIdMeta =
      const VerificationMeta('kasirId');
  @override
  late final GeneratedColumn<String> kasirId = GeneratedColumn<String>(
      'kasir_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        localId,
        type,
        amount,
        note,
        referenceId,
        kasirId,
        createdAt,
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(Insertable<Expense> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    }
    if (data.containsKey('kasir_id')) {
      context.handle(_kasirIdMeta,
          kasirId.isAcceptableOrUnknown(data['kasir_id']!, _kasirIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Expense map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Expense(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_id']),
      kasirId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kasir_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class Expense extends DataClass implements Insertable<Expense> {
  final String id;
  final String localId;
  final String type;
  final int amount;
  final String? note;
  final String? referenceId;
  final String? kasirId;
  final DateTime createdAt;
  final DateTime? syncedAt;
  const Expense(
      {required this.id,
      required this.localId,
      required this.type,
      required this.amount,
      this.note,
      this.referenceId,
      this.kasirId,
      required this.createdAt,
      this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['local_id'] = Variable<String>(localId);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    if (!nullToAbsent || kasirId != null) {
      map['kasir_id'] = Variable<String>(kasirId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      localId: Value(localId),
      type: Value(type),
      amount: Value(amount),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      kasirId: kasirId == null && nullToAbsent
          ? const Value.absent()
          : Value(kasirId),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory Expense.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Expense(
      id: serializer.fromJson<String>(json['id']),
      localId: serializer.fromJson<String>(json['localId']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<int>(json['amount']),
      note: serializer.fromJson<String?>(json['note']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      kasirId: serializer.fromJson<String?>(json['kasirId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'localId': serializer.toJson<String>(localId),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<int>(amount),
      'note': serializer.toJson<String?>(note),
      'referenceId': serializer.toJson<String?>(referenceId),
      'kasirId': serializer.toJson<String?>(kasirId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  Expense copyWith(
          {String? id,
          String? localId,
          String? type,
          int? amount,
          Value<String?> note = const Value.absent(),
          Value<String?> referenceId = const Value.absent(),
          Value<String?> kasirId = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> syncedAt = const Value.absent()}) =>
      Expense(
        id: id ?? this.id,
        localId: localId ?? this.localId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        note: note.present ? note.value : this.note,
        referenceId: referenceId.present ? referenceId.value : this.referenceId,
        kasirId: kasirId.present ? kasirId.value : this.kasirId,
        createdAt: createdAt ?? this.createdAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );
  Expense copyWithCompanion(ExpensesCompanion data) {
    return Expense(
      id: data.id.present ? data.id.value : this.id,
      localId: data.localId.present ? data.localId.value : this.localId,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      note: data.note.present ? data.note.value : this.note,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      kasirId: data.kasirId.present ? data.kasirId.value : this.kasirId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Expense(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('note: $note, ')
          ..write('referenceId: $referenceId, ')
          ..write('kasirId: $kasirId, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, localId, type, amount, note, referenceId,
      kasirId, createdAt, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Expense &&
          other.id == this.id &&
          other.localId == this.localId &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.note == this.note &&
          other.referenceId == this.referenceId &&
          other.kasirId == this.kasirId &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt);
}

class ExpensesCompanion extends UpdateCompanion<Expense> {
  final Value<String> id;
  final Value<String> localId;
  final Value<String> type;
  final Value<int> amount;
  final Value<String?> note;
  final Value<String?> referenceId;
  final Value<String?> kasirId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.localId = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.note = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensesCompanion.insert({
    required String id,
    required String localId,
    required String type,
    required int amount,
    this.note = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        localId = Value(localId),
        type = Value(type),
        amount = Value(amount);
  static Insertable<Expense> custom({
    Expression<String>? id,
    Expression<String>? localId,
    Expression<String>? type,
    Expression<int>? amount,
    Expression<String>? note,
    Expression<String>? referenceId,
    Expression<String>? kasirId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localId != null) 'local_id': localId,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (note != null) 'note': note,
      if (referenceId != null) 'reference_id': referenceId,
      if (kasirId != null) 'kasir_id': kasirId,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensesCompanion copyWith(
      {Value<String>? id,
      Value<String>? localId,
      Value<String>? type,
      Value<int>? amount,
      Value<String?>? note,
      Value<String?>? referenceId,
      Value<String?>? kasirId,
      Value<DateTime>? createdAt,
      Value<DateTime?>? syncedAt,
      Value<int>? rowid}) {
    return ExpensesCompanion(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      referenceId: referenceId ?? this.referenceId,
      kasirId: kasirId ?? this.kasirId,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (kasirId.present) {
      map['kasir_id'] = Variable<String>(kasirId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('note: $note, ')
          ..write('referenceId: $referenceId, ')
          ..write('kasirId: $kasirId, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LoyaltyPointLedgerTable extends LoyaltyPointLedger
    with TableInfo<$LoyaltyPointLedgerTable, LoyaltyPointLedgerData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoyaltyPointLedgerTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _customerIdMeta =
      const VerificationMeta('customerId');
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
      'customer_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pointsMeta = const VerificationMeta('points');
  @override
  late final GeneratedColumn<int> points = GeneratedColumn<int>(
      'points', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
      'reference_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, customerId, type, points, referenceId, note, createdAt, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loyalty_point_ledger';
  @override
  VerificationContext validateIntegrity(
      Insertable<LoyaltyPointLedgerData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
          _customerIdMeta,
          customerId.isAcceptableOrUnknown(
              data['customer_id']!, _customerIdMeta));
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('points')) {
      context.handle(_pointsMeta,
          points.isAcceptableOrUnknown(data['points']!, _pointsMeta));
    } else if (isInserting) {
      context.missing(_pointsMeta);
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LoyaltyPointLedgerData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LoyaltyPointLedgerData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      customerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}customer_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      points: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}points'])!,
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $LoyaltyPointLedgerTable createAlias(String alias) {
    return $LoyaltyPointLedgerTable(attachedDatabase, alias);
  }
}

class LoyaltyPointLedgerData extends DataClass
    implements Insertable<LoyaltyPointLedgerData> {
  final String id;
  final String customerId;
  final String type;
  final int points;
  final String? referenceId;
  final String? note;
  final DateTime createdAt;
  final DateTime? syncedAt;
  const LoyaltyPointLedgerData(
      {required this.id,
      required this.customerId,
      required this.type,
      required this.points,
      this.referenceId,
      this.note,
      required this.createdAt,
      this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['customer_id'] = Variable<String>(customerId);
    map['type'] = Variable<String>(type);
    map['points'] = Variable<int>(points);
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  LoyaltyPointLedgerCompanion toCompanion(bool nullToAbsent) {
    return LoyaltyPointLedgerCompanion(
      id: Value(id),
      customerId: Value(customerId),
      type: Value(type),
      points: Value(points),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory LoyaltyPointLedgerData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LoyaltyPointLedgerData(
      id: serializer.fromJson<String>(json['id']),
      customerId: serializer.fromJson<String>(json['customerId']),
      type: serializer.fromJson<String>(json['type']),
      points: serializer.fromJson<int>(json['points']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'customerId': serializer.toJson<String>(customerId),
      'type': serializer.toJson<String>(type),
      'points': serializer.toJson<int>(points),
      'referenceId': serializer.toJson<String?>(referenceId),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  LoyaltyPointLedgerData copyWith(
          {String? id,
          String? customerId,
          String? type,
          int? points,
          Value<String?> referenceId = const Value.absent(),
          Value<String?> note = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> syncedAt = const Value.absent()}) =>
      LoyaltyPointLedgerData(
        id: id ?? this.id,
        customerId: customerId ?? this.customerId,
        type: type ?? this.type,
        points: points ?? this.points,
        referenceId: referenceId.present ? referenceId.value : this.referenceId,
        note: note.present ? note.value : this.note,
        createdAt: createdAt ?? this.createdAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );
  LoyaltyPointLedgerData copyWithCompanion(LoyaltyPointLedgerCompanion data) {
    return LoyaltyPointLedgerData(
      id: data.id.present ? data.id.value : this.id,
      customerId:
          data.customerId.present ? data.customerId.value : this.customerId,
      type: data.type.present ? data.type.value : this.type,
      points: data.points.present ? data.points.value : this.points,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LoyaltyPointLedgerData(')
          ..write('id: $id, ')
          ..write('customerId: $customerId, ')
          ..write('type: $type, ')
          ..write('points: $points, ')
          ..write('referenceId: $referenceId, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, customerId, type, points, referenceId, note, createdAt, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LoyaltyPointLedgerData &&
          other.id == this.id &&
          other.customerId == this.customerId &&
          other.type == this.type &&
          other.points == this.points &&
          other.referenceId == this.referenceId &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt);
}

class LoyaltyPointLedgerCompanion
    extends UpdateCompanion<LoyaltyPointLedgerData> {
  final Value<String> id;
  final Value<String> customerId;
  final Value<String> type;
  final Value<int> points;
  final Value<String?> referenceId;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const LoyaltyPointLedgerCompanion({
    this.id = const Value.absent(),
    this.customerId = const Value.absent(),
    this.type = const Value.absent(),
    this.points = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoyaltyPointLedgerCompanion.insert({
    required String id,
    required String customerId,
    required String type,
    required int points,
    this.referenceId = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        customerId = Value(customerId),
        type = Value(type),
        points = Value(points);
  static Insertable<LoyaltyPointLedgerData> custom({
    Expression<String>? id,
    Expression<String>? customerId,
    Expression<String>? type,
    Expression<int>? points,
    Expression<String>? referenceId,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (customerId != null) 'customer_id': customerId,
      if (type != null) 'type': type,
      if (points != null) 'points': points,
      if (referenceId != null) 'reference_id': referenceId,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoyaltyPointLedgerCompanion copyWith(
      {Value<String>? id,
      Value<String>? customerId,
      Value<String>? type,
      Value<int>? points,
      Value<String?>? referenceId,
      Value<String?>? note,
      Value<DateTime>? createdAt,
      Value<DateTime?>? syncedAt,
      Value<int>? rowid}) {
    return LoyaltyPointLedgerCompanion(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      type: type ?? this.type,
      points: points ?? this.points,
      referenceId: referenceId ?? this.referenceId,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (points.present) {
      map['points'] = Variable<int>(points.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoyaltyPointLedgerCompanion(')
          ..write('id: $id, ')
          ..write('customerId: $customerId, ')
          ..write('type: $type, ')
          ..write('points: $points, ')
          ..write('referenceId: $referenceId, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SuppliersTable extends Suppliers
    with TableInfo<$SuppliersTable, Supplier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SuppliersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _outstandingDebtMeta =
      const VerificationMeta('outstandingDebt');
  @override
  late final GeneratedColumn<int> outstandingDebt = GeneratedColumn<int>(
      'outstanding_debt', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, phone, outstandingDebt, notes, isActive, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'suppliers';
  @override
  VerificationContext validateIntegrity(Insertable<Supplier> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('outstanding_debt')) {
      context.handle(
          _outstandingDebtMeta,
          outstandingDebt.isAcceptableOrUnknown(
              data['outstanding_debt']!, _outstandingDebtMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Supplier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Supplier(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
      outstandingDebt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}outstanding_debt'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $SuppliersTable createAlias(String alias) {
    return $SuppliersTable(attachedDatabase, alias);
  }
}

class Supplier extends DataClass implements Insertable<Supplier> {
  final String id;
  final String name;
  final String? phone;
  final int outstandingDebt;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  const Supplier(
      {required this.id,
      required this.name,
      this.phone,
      required this.outstandingDebt,
      this.notes,
      required this.isActive,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    map['outstanding_debt'] = Variable<int>(outstandingDebt);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SuppliersCompanion toCompanion(bool nullToAbsent) {
    return SuppliersCompanion(
      id: Value(id),
      name: Value(name),
      phone:
          phone == null && nullToAbsent ? const Value.absent() : Value(phone),
      outstandingDebt: Value(outstandingDebt),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Supplier.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Supplier(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      outstandingDebt: serializer.fromJson<int>(json['outstandingDebt']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'outstandingDebt': serializer.toJson<int>(outstandingDebt),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Supplier copyWith(
          {String? id,
          String? name,
          Value<String?> phone = const Value.absent(),
          int? outstandingDebt,
          Value<String?> notes = const Value.absent(),
          bool? isActive,
          DateTime? createdAt}) =>
      Supplier(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone.present ? phone.value : this.phone,
        outstandingDebt: outstandingDebt ?? this.outstandingDebt,
        notes: notes.present ? notes.value : this.notes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
      );
  Supplier copyWithCompanion(SuppliersCompanion data) {
    return Supplier(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      outstandingDebt: data.outstandingDebt.present
          ? data.outstandingDebt.value
          : this.outstandingDebt,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Supplier(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('outstandingDebt: $outstandingDebt, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, phone, outstandingDebt, notes, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Supplier &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.outstandingDebt == this.outstandingDebt &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class SuppliersCompanion extends UpdateCompanion<Supplier> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> phone;
  final Value<int> outstandingDebt;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SuppliersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.outstandingDebt = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SuppliersCompanion.insert({
    required String id,
    required String name,
    this.phone = const Value.absent(),
    this.outstandingDebt = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<Supplier> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<int>? outstandingDebt,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (outstandingDebt != null) 'outstanding_debt': outstandingDebt,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SuppliersCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? phone,
      Value<int>? outstandingDebt,
      Value<String?>? notes,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return SuppliersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      outstandingDebt: outstandingDebt ?? this.outstandingDebt,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (outstandingDebt.present) {
      map['outstanding_debt'] = Variable<int>(outstandingDebt.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SuppliersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('outstandingDebt: $outstandingDebt, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchasesTable extends Purchases
    with TableInfo<$PurchasesTable, Purchase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
      'local_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _supplierIdMeta =
      const VerificationMeta('supplierId');
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
      'supplier_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _kasirIdMeta =
      const VerificationMeta('kasirId');
  @override
  late final GeneratedColumn<String> kasirId = GeneratedColumn<String>(
      'kasir_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<int> total = GeneratedColumn<int>(
      'total', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _paidMeta = const VerificationMeta('paid');
  @override
  late final GeneratedColumn<int> paid = GeneratedColumn<int>(
      'paid', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        localId,
        supplierId,
        kasirId,
        status,
        total,
        paid,
        note,
        createdAt,
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchases';
  @override
  VerificationContext validateIntegrity(Insertable<Purchase> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
          _supplierIdMeta,
          supplierId.isAcceptableOrUnknown(
              data['supplier_id']!, _supplierIdMeta));
    }
    if (data.containsKey('kasir_id')) {
      context.handle(_kasirIdMeta,
          kasirId.isAcceptableOrUnknown(data['kasir_id']!, _kasirIdMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('total')) {
      context.handle(
          _totalMeta, total.isAcceptableOrUnknown(data['total']!, _totalMeta));
    }
    if (data.containsKey('paid')) {
      context.handle(
          _paidMeta, paid.isAcceptableOrUnknown(data['paid']!, _paidMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Purchase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Purchase(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_id'])!,
      supplierId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}supplier_id']),
      kasirId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kasir_id']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      total: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total'])!,
      paid: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}paid'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $PurchasesTable createAlias(String alias) {
    return $PurchasesTable(attachedDatabase, alias);
  }
}

class Purchase extends DataClass implements Insertable<Purchase> {
  final String id;
  final String localId;
  final String? supplierId;
  final String? kasirId;
  final String status;
  final int total;
  final int paid;
  final String? note;
  final DateTime createdAt;
  final DateTime? syncedAt;
  const Purchase(
      {required this.id,
      required this.localId,
      this.supplierId,
      this.kasirId,
      required this.status,
      required this.total,
      required this.paid,
      this.note,
      required this.createdAt,
      this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || supplierId != null) {
      map['supplier_id'] = Variable<String>(supplierId);
    }
    if (!nullToAbsent || kasirId != null) {
      map['kasir_id'] = Variable<String>(kasirId);
    }
    map['status'] = Variable<String>(status);
    map['total'] = Variable<int>(total);
    map['paid'] = Variable<int>(paid);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  PurchasesCompanion toCompanion(bool nullToAbsent) {
    return PurchasesCompanion(
      id: Value(id),
      localId: Value(localId),
      supplierId: supplierId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplierId),
      kasirId: kasirId == null && nullToAbsent
          ? const Value.absent()
          : Value(kasirId),
      status: Value(status),
      total: Value(total),
      paid: Value(paid),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory Purchase.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Purchase(
      id: serializer.fromJson<String>(json['id']),
      localId: serializer.fromJson<String>(json['localId']),
      supplierId: serializer.fromJson<String?>(json['supplierId']),
      kasirId: serializer.fromJson<String?>(json['kasirId']),
      status: serializer.fromJson<String>(json['status']),
      total: serializer.fromJson<int>(json['total']),
      paid: serializer.fromJson<int>(json['paid']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'localId': serializer.toJson<String>(localId),
      'supplierId': serializer.toJson<String?>(supplierId),
      'kasirId': serializer.toJson<String?>(kasirId),
      'status': serializer.toJson<String>(status),
      'total': serializer.toJson<int>(total),
      'paid': serializer.toJson<int>(paid),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  Purchase copyWith(
          {String? id,
          String? localId,
          Value<String?> supplierId = const Value.absent(),
          Value<String?> kasirId = const Value.absent(),
          String? status,
          int? total,
          int? paid,
          Value<String?> note = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> syncedAt = const Value.absent()}) =>
      Purchase(
        id: id ?? this.id,
        localId: localId ?? this.localId,
        supplierId: supplierId.present ? supplierId.value : this.supplierId,
        kasirId: kasirId.present ? kasirId.value : this.kasirId,
        status: status ?? this.status,
        total: total ?? this.total,
        paid: paid ?? this.paid,
        note: note.present ? note.value : this.note,
        createdAt: createdAt ?? this.createdAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );
  Purchase copyWithCompanion(PurchasesCompanion data) {
    return Purchase(
      id: data.id.present ? data.id.value : this.id,
      localId: data.localId.present ? data.localId.value : this.localId,
      supplierId:
          data.supplierId.present ? data.supplierId.value : this.supplierId,
      kasirId: data.kasirId.present ? data.kasirId.value : this.kasirId,
      status: data.status.present ? data.status.value : this.status,
      total: data.total.present ? data.total.value : this.total,
      paid: data.paid.present ? data.paid.value : this.paid,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Purchase(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('supplierId: $supplierId, ')
          ..write('kasirId: $kasirId, ')
          ..write('status: $status, ')
          ..write('total: $total, ')
          ..write('paid: $paid, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, localId, supplierId, kasirId, status,
      total, paid, note, createdAt, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Purchase &&
          other.id == this.id &&
          other.localId == this.localId &&
          other.supplierId == this.supplierId &&
          other.kasirId == this.kasirId &&
          other.status == this.status &&
          other.total == this.total &&
          other.paid == this.paid &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt);
}

class PurchasesCompanion extends UpdateCompanion<Purchase> {
  final Value<String> id;
  final Value<String> localId;
  final Value<String?> supplierId;
  final Value<String?> kasirId;
  final Value<String> status;
  final Value<int> total;
  final Value<int> paid;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const PurchasesCompanion({
    this.id = const Value.absent(),
    this.localId = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.kasirId = const Value.absent(),
    this.status = const Value.absent(),
    this.total = const Value.absent(),
    this.paid = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchasesCompanion.insert({
    required String id,
    required String localId,
    this.supplierId = const Value.absent(),
    this.kasirId = const Value.absent(),
    required String status,
    this.total = const Value.absent(),
    this.paid = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        localId = Value(localId),
        status = Value(status);
  static Insertable<Purchase> custom({
    Expression<String>? id,
    Expression<String>? localId,
    Expression<String>? supplierId,
    Expression<String>? kasirId,
    Expression<String>? status,
    Expression<int>? total,
    Expression<int>? paid,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localId != null) 'local_id': localId,
      if (supplierId != null) 'supplier_id': supplierId,
      if (kasirId != null) 'kasir_id': kasirId,
      if (status != null) 'status': status,
      if (total != null) 'total': total,
      if (paid != null) 'paid': paid,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchasesCompanion copyWith(
      {Value<String>? id,
      Value<String>? localId,
      Value<String?>? supplierId,
      Value<String?>? kasirId,
      Value<String>? status,
      Value<int>? total,
      Value<int>? paid,
      Value<String?>? note,
      Value<DateTime>? createdAt,
      Value<DateTime?>? syncedAt,
      Value<int>? rowid}) {
    return PurchasesCompanion(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      supplierId: supplierId ?? this.supplierId,
      kasirId: kasirId ?? this.kasirId,
      status: status ?? this.status,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (kasirId.present) {
      map['kasir_id'] = Variable<String>(kasirId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (total.present) {
      map['total'] = Variable<int>(total.value);
    }
    if (paid.present) {
      map['paid'] = Variable<int>(paid.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchasesCompanion(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('supplierId: $supplierId, ')
          ..write('kasirId: $kasirId, ')
          ..write('status: $status, ')
          ..write('total: $total, ')
          ..write('paid: $paid, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseItemsTable extends PurchaseItems
    with TableInfo<$PurchaseItemsTable, PurchaseItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _purchaseIdMeta =
      const VerificationMeta('purchaseId');
  @override
  late final GeneratedColumn<String> purchaseId = GeneratedColumn<String>(
      'purchase_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES purchases (id)'));
  static const VerificationMeta _productUnitIdMeta =
      const VerificationMeta('productUnitId');
  @override
  late final GeneratedColumn<String> productUnitId = GeneratedColumn<String>(
      'product_unit_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<double> qty = GeneratedColumn<double>(
      'qty', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pricePerUnitMeta =
      const VerificationMeta('pricePerUnit');
  @override
  late final GeneratedColumn<int> pricePerUnit = GeneratedColumn<int>(
      'price_per_unit', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _subtotalMeta =
      const VerificationMeta('subtotal');
  @override
  late final GeneratedColumn<int> subtotal = GeneratedColumn<int>(
      'subtotal', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, purchaseId, productUnitId, qty, pricePerUnit, subtotal];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchase_items';
  @override
  VerificationContext validateIntegrity(Insertable<PurchaseItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('purchase_id')) {
      context.handle(
          _purchaseIdMeta,
          purchaseId.isAcceptableOrUnknown(
              data['purchase_id']!, _purchaseIdMeta));
    } else if (isInserting) {
      context.missing(_purchaseIdMeta);
    }
    if (data.containsKey('product_unit_id')) {
      context.handle(
          _productUnitIdMeta,
          productUnitId.isAcceptableOrUnknown(
              data['product_unit_id']!, _productUnitIdMeta));
    } else if (isInserting) {
      context.missing(_productUnitIdMeta);
    }
    if (data.containsKey('qty')) {
      context.handle(
          _qtyMeta, qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta));
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('price_per_unit')) {
      context.handle(
          _pricePerUnitMeta,
          pricePerUnit.isAcceptableOrUnknown(
              data['price_per_unit']!, _pricePerUnitMeta));
    } else if (isInserting) {
      context.missing(_pricePerUnitMeta);
    }
    if (data.containsKey('subtotal')) {
      context.handle(_subtotalMeta,
          subtotal.isAcceptableOrUnknown(data['subtotal']!, _subtotalMeta));
    } else if (isInserting) {
      context.missing(_subtotalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurchaseItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      purchaseId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}purchase_id'])!,
      productUnitId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_unit_id'])!,
      qty: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}qty'])!,
      pricePerUnit: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price_per_unit'])!,
      subtotal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}subtotal'])!,
    );
  }

  @override
  $PurchaseItemsTable createAlias(String alias) {
    return $PurchaseItemsTable(attachedDatabase, alias);
  }
}

class PurchaseItem extends DataClass implements Insertable<PurchaseItem> {
  final String id;
  final String purchaseId;
  final String productUnitId;
  final double qty;
  final int pricePerUnit;
  final int subtotal;
  const PurchaseItem(
      {required this.id,
      required this.purchaseId,
      required this.productUnitId,
      required this.qty,
      required this.pricePerUnit,
      required this.subtotal});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['purchase_id'] = Variable<String>(purchaseId);
    map['product_unit_id'] = Variable<String>(productUnitId);
    map['qty'] = Variable<double>(qty);
    map['price_per_unit'] = Variable<int>(pricePerUnit);
    map['subtotal'] = Variable<int>(subtotal);
    return map;
  }

  PurchaseItemsCompanion toCompanion(bool nullToAbsent) {
    return PurchaseItemsCompanion(
      id: Value(id),
      purchaseId: Value(purchaseId),
      productUnitId: Value(productUnitId),
      qty: Value(qty),
      pricePerUnit: Value(pricePerUnit),
      subtotal: Value(subtotal),
    );
  }

  factory PurchaseItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseItem(
      id: serializer.fromJson<String>(json['id']),
      purchaseId: serializer.fromJson<String>(json['purchaseId']),
      productUnitId: serializer.fromJson<String>(json['productUnitId']),
      qty: serializer.fromJson<double>(json['qty']),
      pricePerUnit: serializer.fromJson<int>(json['pricePerUnit']),
      subtotal: serializer.fromJson<int>(json['subtotal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'purchaseId': serializer.toJson<String>(purchaseId),
      'productUnitId': serializer.toJson<String>(productUnitId),
      'qty': serializer.toJson<double>(qty),
      'pricePerUnit': serializer.toJson<int>(pricePerUnit),
      'subtotal': serializer.toJson<int>(subtotal),
    };
  }

  PurchaseItem copyWith(
          {String? id,
          String? purchaseId,
          String? productUnitId,
          double? qty,
          int? pricePerUnit,
          int? subtotal}) =>
      PurchaseItem(
        id: id ?? this.id,
        purchaseId: purchaseId ?? this.purchaseId,
        productUnitId: productUnitId ?? this.productUnitId,
        qty: qty ?? this.qty,
        pricePerUnit: pricePerUnit ?? this.pricePerUnit,
        subtotal: subtotal ?? this.subtotal,
      );
  PurchaseItem copyWithCompanion(PurchaseItemsCompanion data) {
    return PurchaseItem(
      id: data.id.present ? data.id.value : this.id,
      purchaseId:
          data.purchaseId.present ? data.purchaseId.value : this.purchaseId,
      productUnitId: data.productUnitId.present
          ? data.productUnitId.value
          : this.productUnitId,
      qty: data.qty.present ? data.qty.value : this.qty,
      pricePerUnit: data.pricePerUnit.present
          ? data.pricePerUnit.value
          : this.pricePerUnit,
      subtotal: data.subtotal.present ? data.subtotal.value : this.subtotal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseItem(')
          ..write('id: $id, ')
          ..write('purchaseId: $purchaseId, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('qty: $qty, ')
          ..write('pricePerUnit: $pricePerUnit, ')
          ..write('subtotal: $subtotal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, purchaseId, productUnitId, qty, pricePerUnit, subtotal);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseItem &&
          other.id == this.id &&
          other.purchaseId == this.purchaseId &&
          other.productUnitId == this.productUnitId &&
          other.qty == this.qty &&
          other.pricePerUnit == this.pricePerUnit &&
          other.subtotal == this.subtotal);
}

class PurchaseItemsCompanion extends UpdateCompanion<PurchaseItem> {
  final Value<String> id;
  final Value<String> purchaseId;
  final Value<String> productUnitId;
  final Value<double> qty;
  final Value<int> pricePerUnit;
  final Value<int> subtotal;
  final Value<int> rowid;
  const PurchaseItemsCompanion({
    this.id = const Value.absent(),
    this.purchaseId = const Value.absent(),
    this.productUnitId = const Value.absent(),
    this.qty = const Value.absent(),
    this.pricePerUnit = const Value.absent(),
    this.subtotal = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseItemsCompanion.insert({
    required String id,
    required String purchaseId,
    required String productUnitId,
    required double qty,
    required int pricePerUnit,
    required int subtotal,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        purchaseId = Value(purchaseId),
        productUnitId = Value(productUnitId),
        qty = Value(qty),
        pricePerUnit = Value(pricePerUnit),
        subtotal = Value(subtotal);
  static Insertable<PurchaseItem> custom({
    Expression<String>? id,
    Expression<String>? purchaseId,
    Expression<String>? productUnitId,
    Expression<double>? qty,
    Expression<int>? pricePerUnit,
    Expression<int>? subtotal,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (purchaseId != null) 'purchase_id': purchaseId,
      if (productUnitId != null) 'product_unit_id': productUnitId,
      if (qty != null) 'qty': qty,
      if (pricePerUnit != null) 'price_per_unit': pricePerUnit,
      if (subtotal != null) 'subtotal': subtotal,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? purchaseId,
      Value<String>? productUnitId,
      Value<double>? qty,
      Value<int>? pricePerUnit,
      Value<int>? subtotal,
      Value<int>? rowid}) {
    return PurchaseItemsCompanion(
      id: id ?? this.id,
      purchaseId: purchaseId ?? this.purchaseId,
      productUnitId: productUnitId ?? this.productUnitId,
      qty: qty ?? this.qty,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      subtotal: subtotal ?? this.subtotal,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (purchaseId.present) {
      map['purchase_id'] = Variable<String>(purchaseId.value);
    }
    if (productUnitId.present) {
      map['product_unit_id'] = Variable<String>(productUnitId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<double>(qty.value);
    }
    if (pricePerUnit.present) {
      map['price_per_unit'] = Variable<int>(pricePerUnit.value);
    }
    if (subtotal.present) {
      map['subtotal'] = Variable<int>(subtotal.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseItemsCompanion(')
          ..write('id: $id, ')
          ..write('purchaseId: $purchaseId, ')
          ..write('productUnitId: $productUnitId, ')
          ..write('qty: $qty, ')
          ..write('pricePerUnit: $pricePerUnit, ')
          ..write('subtotal: $subtotal, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KasirPermissionsTable extends KasirPermissions
    with TableInfo<$KasirPermissionsTable, KasirPermission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KasirPermissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _permissionKeyMeta =
      const VerificationMeta('permissionKey');
  @override
  late final GeneratedColumn<String> permissionKey = GeneratedColumn<String>(
      'permission_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isEnabledMeta =
      const VerificationMeta('isEnabled');
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
      'is_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [permissionKey, isEnabled, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kasir_permissions';
  @override
  VerificationContext validateIntegrity(Insertable<KasirPermission> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('permission_key')) {
      context.handle(
          _permissionKeyMeta,
          permissionKey.isAcceptableOrUnknown(
              data['permission_key']!, _permissionKeyMeta));
    } else if (isInserting) {
      context.missing(_permissionKeyMeta);
    }
    if (data.containsKey('is_enabled')) {
      context.handle(_isEnabledMeta,
          isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {permissionKey};
  @override
  KasirPermission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KasirPermission(
      permissionKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}permission_key'])!,
      isEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_enabled'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $KasirPermissionsTable createAlias(String alias) {
    return $KasirPermissionsTable(attachedDatabase, alias);
  }
}

class KasirPermission extends DataClass implements Insertable<KasirPermission> {
  final String permissionKey;
  final bool isEnabled;
  final DateTime updatedAt;
  const KasirPermission(
      {required this.permissionKey,
      required this.isEnabled,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['permission_key'] = Variable<String>(permissionKey);
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KasirPermissionsCompanion toCompanion(bool nullToAbsent) {
    return KasirPermissionsCompanion(
      permissionKey: Value(permissionKey),
      isEnabled: Value(isEnabled),
      updatedAt: Value(updatedAt),
    );
  }

  factory KasirPermission.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KasirPermission(
      permissionKey: serializer.fromJson<String>(json['permissionKey']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'permissionKey': serializer.toJson<String>(permissionKey),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  KasirPermission copyWith(
          {String? permissionKey, bool? isEnabled, DateTime? updatedAt}) =>
      KasirPermission(
        permissionKey: permissionKey ?? this.permissionKey,
        isEnabled: isEnabled ?? this.isEnabled,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  KasirPermission copyWithCompanion(KasirPermissionsCompanion data) {
    return KasirPermission(
      permissionKey: data.permissionKey.present
          ? data.permissionKey.value
          : this.permissionKey,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KasirPermission(')
          ..write('permissionKey: $permissionKey, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(permissionKey, isEnabled, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KasirPermission &&
          other.permissionKey == this.permissionKey &&
          other.isEnabled == this.isEnabled &&
          other.updatedAt == this.updatedAt);
}

class KasirPermissionsCompanion extends UpdateCompanion<KasirPermission> {
  final Value<String> permissionKey;
  final Value<bool> isEnabled;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const KasirPermissionsCompanion({
    this.permissionKey = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KasirPermissionsCompanion.insert({
    required String permissionKey,
    this.isEnabled = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : permissionKey = Value(permissionKey);
  static Insertable<KasirPermission> custom({
    Expression<String>? permissionKey,
    Expression<bool>? isEnabled,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (permissionKey != null) 'permission_key': permissionKey,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KasirPermissionsCompanion copyWith(
      {Value<String>? permissionKey,
      Value<bool>? isEnabled,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return KasirPermissionsCompanion(
      permissionKey: permissionKey ?? this.permissionKey,
      isEnabled: isEnabled ?? this.isEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (permissionKey.present) {
      map['permission_key'] = Variable<String>(permissionKey.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KasirPermissionsCompanion(')
          ..write('permissionKey: $permissionKey, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PaymentMethodsTable extends PaymentMethods
    with TableInfo<$PaymentMethodsTable, PaymentMethod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentMethodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _qrValueMeta =
      const VerificationMeta('qrValue');
  @override
  late final GeneratedColumn<String> qrValue = GeneratedColumn<String>(
      'qr_value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, type, name, data, qrValue, isActive, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payment_methods';
  @override
  VerificationContext validateIntegrity(Insertable<PaymentMethod> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    }
    if (data.containsKey('qr_value')) {
      context.handle(_qrValueMeta,
          qrValue.isAcceptableOrUnknown(data['qr_value']!, _qrValueMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PaymentMethod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaymentMethod(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data']),
      qrValue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}qr_value']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $PaymentMethodsTable createAlias(String alias) {
    return $PaymentMethodsTable(attachedDatabase, alias);
  }
}

class PaymentMethod extends DataClass implements Insertable<PaymentMethod> {
  final String id;
  final String type;
  final String name;
  final String? data;
  final String? qrValue;
  final bool isActive;
  final int sortOrder;
  const PaymentMethod(
      {required this.id,
      required this.type,
      required this.name,
      this.data,
      this.qrValue,
      required this.isActive,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || data != null) {
      map['data'] = Variable<String>(data);
    }
    if (!nullToAbsent || qrValue != null) {
      map['qr_value'] = Variable<String>(qrValue);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  PaymentMethodsCompanion toCompanion(bool nullToAbsent) {
    return PaymentMethodsCompanion(
      id: Value(id),
      type: Value(type),
      name: Value(name),
      data: data == null && nullToAbsent ? const Value.absent() : Value(data),
      qrValue: qrValue == null && nullToAbsent
          ? const Value.absent()
          : Value(qrValue),
      isActive: Value(isActive),
      sortOrder: Value(sortOrder),
    );
  }

  factory PaymentMethod.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaymentMethod(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      data: serializer.fromJson<String?>(json['data']),
      qrValue: serializer.fromJson<String?>(json['qrValue']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'data': serializer.toJson<String?>(data),
      'qrValue': serializer.toJson<String?>(qrValue),
      'isActive': serializer.toJson<bool>(isActive),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  PaymentMethod copyWith(
          {String? id,
          String? type,
          String? name,
          Value<String?> data = const Value.absent(),
          Value<String?> qrValue = const Value.absent(),
          bool? isActive,
          int? sortOrder}) =>
      PaymentMethod(
        id: id ?? this.id,
        type: type ?? this.type,
        name: name ?? this.name,
        data: data.present ? data.value : this.data,
        qrValue: qrValue.present ? qrValue.value : this.qrValue,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  PaymentMethod copyWithCompanion(PaymentMethodsCompanion data) {
    return PaymentMethod(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      data: data.data.present ? data.data.value : this.data,
      qrValue: data.qrValue.present ? data.qrValue.value : this.qrValue,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaymentMethod(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('data: $data, ')
          ..write('qrValue: $qrValue, ')
          ..write('isActive: $isActive, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, type, name, data, qrValue, isActive, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaymentMethod &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.data == this.data &&
          other.qrValue == this.qrValue &&
          other.isActive == this.isActive &&
          other.sortOrder == this.sortOrder);
}

class PaymentMethodsCompanion extends UpdateCompanion<PaymentMethod> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> name;
  final Value<String?> data;
  final Value<String?> qrValue;
  final Value<bool> isActive;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const PaymentMethodsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.data = const Value.absent(),
    this.qrValue = const Value.absent(),
    this.isActive = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PaymentMethodsCompanion.insert({
    required String id,
    required String type,
    required String name,
    this.data = const Value.absent(),
    this.qrValue = const Value.absent(),
    this.isActive = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        name = Value(name);
  static Insertable<PaymentMethod> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? data,
    Expression<String>? qrValue,
    Expression<bool>? isActive,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (data != null) 'data': data,
      if (qrValue != null) 'qr_value': qrValue,
      if (isActive != null) 'is_active': isActive,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PaymentMethodsCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String>? name,
      Value<String?>? data,
      Value<String?>? qrValue,
      Value<bool>? isActive,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return PaymentMethodsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      data: data ?? this.data,
      qrValue: qrValue ?? this.qrValue,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (qrValue.present) {
      map['qr_value'] = Variable<String>(qrValue.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentMethodsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('data: $data, ')
          ..write('qrValue: $qrValue, ')
          ..write('isActive: $isActive, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailySummariesTable extends DailySummaries
    with TableInfo<$DailySummariesTable, DailySummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailySummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _omzetMeta = const VerificationMeta('omzet');
  @override
  late final GeneratedColumn<int> omzet = GeneratedColumn<int>(
      'omzet', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _hppMeta = const VerificationMeta('hpp');
  @override
  late final GeneratedColumn<int> hpp = GeneratedColumn<int>(
      'hpp', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _labaKotorMeta =
      const VerificationMeta('labaKotor');
  @override
  late final GeneratedColumn<int> labaKotor = GeneratedColumn<int>(
      'laba_kotor', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _jumlahTransaksiMeta =
      const VerificationMeta('jumlahTransaksi');
  @override
  late final GeneratedColumn<int> jumlahTransaksi = GeneratedColumn<int>(
      'jumlah_transaksi', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _jumlahItemMeta =
      const VerificationMeta('jumlahItem');
  @override
  late final GeneratedColumn<int> jumlahItem = GeneratedColumn<int>(
      'jumlah_item', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pembayaranTunaiMeta =
      const VerificationMeta('pembayaranTunai');
  @override
  late final GeneratedColumn<int> pembayaranTunai = GeneratedColumn<int>(
      'pembayaran_tunai', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pembayaranQrisMeta =
      const VerificationMeta('pembayaranQris');
  @override
  late final GeneratedColumn<int> pembayaranQris = GeneratedColumn<int>(
      'pembayaran_qris', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pembayaranTransferMeta =
      const VerificationMeta('pembayaranTransfer');
  @override
  late final GeneratedColumn<int> pembayaranTransfer = GeneratedColumn<int>(
      'pembayaran_transfer', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pembayaranLainnyaMeta =
      const VerificationMeta('pembayaranLainnya');
  @override
  late final GeneratedColumn<int> pembayaranLainnya = GeneratedColumn<int>(
      'pembayaran_lainnya', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        date,
        omzet,
        hpp,
        labaKotor,
        jumlahTransaksi,
        jumlahItem,
        pembayaranTunai,
        pembayaranQris,
        pembayaranTransfer,
        pembayaranLainnya,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_summaries';
  @override
  VerificationContext validateIntegrity(Insertable<DailySummary> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('omzet')) {
      context.handle(
          _omzetMeta, omzet.isAcceptableOrUnknown(data['omzet']!, _omzetMeta));
    }
    if (data.containsKey('hpp')) {
      context.handle(
          _hppMeta, hpp.isAcceptableOrUnknown(data['hpp']!, _hppMeta));
    }
    if (data.containsKey('laba_kotor')) {
      context.handle(_labaKotorMeta,
          labaKotor.isAcceptableOrUnknown(data['laba_kotor']!, _labaKotorMeta));
    }
    if (data.containsKey('jumlah_transaksi')) {
      context.handle(
          _jumlahTransaksiMeta,
          jumlahTransaksi.isAcceptableOrUnknown(
              data['jumlah_transaksi']!, _jumlahTransaksiMeta));
    }
    if (data.containsKey('jumlah_item')) {
      context.handle(
          _jumlahItemMeta,
          jumlahItem.isAcceptableOrUnknown(
              data['jumlah_item']!, _jumlahItemMeta));
    }
    if (data.containsKey('pembayaran_tunai')) {
      context.handle(
          _pembayaranTunaiMeta,
          pembayaranTunai.isAcceptableOrUnknown(
              data['pembayaran_tunai']!, _pembayaranTunaiMeta));
    }
    if (data.containsKey('pembayaran_qris')) {
      context.handle(
          _pembayaranQrisMeta,
          pembayaranQris.isAcceptableOrUnknown(
              data['pembayaran_qris']!, _pembayaranQrisMeta));
    }
    if (data.containsKey('pembayaran_transfer')) {
      context.handle(
          _pembayaranTransferMeta,
          pembayaranTransfer.isAcceptableOrUnknown(
              data['pembayaran_transfer']!, _pembayaranTransferMeta));
    }
    if (data.containsKey('pembayaran_lainnya')) {
      context.handle(
          _pembayaranLainnyaMeta,
          pembayaranLainnya.isAcceptableOrUnknown(
              data['pembayaran_lainnya']!, _pembayaranLainnyaMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DailySummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailySummary(
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      omzet: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}omzet'])!,
      hpp: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hpp'])!,
      labaKotor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}laba_kotor'])!,
      jumlahTransaksi: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}jumlah_transaksi'])!,
      jumlahItem: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}jumlah_item'])!,
      pembayaranTunai: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pembayaran_tunai'])!,
      pembayaranQris: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pembayaran_qris'])!,
      pembayaranTransfer: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}pembayaran_transfer'])!,
      pembayaranLainnya: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}pembayaran_lainnya'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $DailySummariesTable createAlias(String alias) {
    return $DailySummariesTable(attachedDatabase, alias);
  }
}

class DailySummary extends DataClass implements Insertable<DailySummary> {
  /// 'YYYY-MM-DD' (zona waktu lokal device).
  final String date;
  final int omzet;
  final int hpp;
  final int labaKotor;
  final int jumlahTransaksi;
  final int jumlahItem;
  final int pembayaranTunai;
  final int pembayaranQris;
  final int pembayaranTransfer;
  final int pembayaranLainnya;
  final DateTime updatedAt;
  const DailySummary(
      {required this.date,
      required this.omzet,
      required this.hpp,
      required this.labaKotor,
      required this.jumlahTransaksi,
      required this.jumlahItem,
      required this.pembayaranTunai,
      required this.pembayaranQris,
      required this.pembayaranTransfer,
      required this.pembayaranLainnya,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['omzet'] = Variable<int>(omzet);
    map['hpp'] = Variable<int>(hpp);
    map['laba_kotor'] = Variable<int>(labaKotor);
    map['jumlah_transaksi'] = Variable<int>(jumlahTransaksi);
    map['jumlah_item'] = Variable<int>(jumlahItem);
    map['pembayaran_tunai'] = Variable<int>(pembayaranTunai);
    map['pembayaran_qris'] = Variable<int>(pembayaranQris);
    map['pembayaran_transfer'] = Variable<int>(pembayaranTransfer);
    map['pembayaran_lainnya'] = Variable<int>(pembayaranLainnya);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DailySummariesCompanion toCompanion(bool nullToAbsent) {
    return DailySummariesCompanion(
      date: Value(date),
      omzet: Value(omzet),
      hpp: Value(hpp),
      labaKotor: Value(labaKotor),
      jumlahTransaksi: Value(jumlahTransaksi),
      jumlahItem: Value(jumlahItem),
      pembayaranTunai: Value(pembayaranTunai),
      pembayaranQris: Value(pembayaranQris),
      pembayaranTransfer: Value(pembayaranTransfer),
      pembayaranLainnya: Value(pembayaranLainnya),
      updatedAt: Value(updatedAt),
    );
  }

  factory DailySummary.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailySummary(
      date: serializer.fromJson<String>(json['date']),
      omzet: serializer.fromJson<int>(json['omzet']),
      hpp: serializer.fromJson<int>(json['hpp']),
      labaKotor: serializer.fromJson<int>(json['labaKotor']),
      jumlahTransaksi: serializer.fromJson<int>(json['jumlahTransaksi']),
      jumlahItem: serializer.fromJson<int>(json['jumlahItem']),
      pembayaranTunai: serializer.fromJson<int>(json['pembayaranTunai']),
      pembayaranQris: serializer.fromJson<int>(json['pembayaranQris']),
      pembayaranTransfer: serializer.fromJson<int>(json['pembayaranTransfer']),
      pembayaranLainnya: serializer.fromJson<int>(json['pembayaranLainnya']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'omzet': serializer.toJson<int>(omzet),
      'hpp': serializer.toJson<int>(hpp),
      'labaKotor': serializer.toJson<int>(labaKotor),
      'jumlahTransaksi': serializer.toJson<int>(jumlahTransaksi),
      'jumlahItem': serializer.toJson<int>(jumlahItem),
      'pembayaranTunai': serializer.toJson<int>(pembayaranTunai),
      'pembayaranQris': serializer.toJson<int>(pembayaranQris),
      'pembayaranTransfer': serializer.toJson<int>(pembayaranTransfer),
      'pembayaranLainnya': serializer.toJson<int>(pembayaranLainnya),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DailySummary copyWith(
          {String? date,
          int? omzet,
          int? hpp,
          int? labaKotor,
          int? jumlahTransaksi,
          int? jumlahItem,
          int? pembayaranTunai,
          int? pembayaranQris,
          int? pembayaranTransfer,
          int? pembayaranLainnya,
          DateTime? updatedAt}) =>
      DailySummary(
        date: date ?? this.date,
        omzet: omzet ?? this.omzet,
        hpp: hpp ?? this.hpp,
        labaKotor: labaKotor ?? this.labaKotor,
        jumlahTransaksi: jumlahTransaksi ?? this.jumlahTransaksi,
        jumlahItem: jumlahItem ?? this.jumlahItem,
        pembayaranTunai: pembayaranTunai ?? this.pembayaranTunai,
        pembayaranQris: pembayaranQris ?? this.pembayaranQris,
        pembayaranTransfer: pembayaranTransfer ?? this.pembayaranTransfer,
        pembayaranLainnya: pembayaranLainnya ?? this.pembayaranLainnya,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  DailySummary copyWithCompanion(DailySummariesCompanion data) {
    return DailySummary(
      date: data.date.present ? data.date.value : this.date,
      omzet: data.omzet.present ? data.omzet.value : this.omzet,
      hpp: data.hpp.present ? data.hpp.value : this.hpp,
      labaKotor: data.labaKotor.present ? data.labaKotor.value : this.labaKotor,
      jumlahTransaksi: data.jumlahTransaksi.present
          ? data.jumlahTransaksi.value
          : this.jumlahTransaksi,
      jumlahItem:
          data.jumlahItem.present ? data.jumlahItem.value : this.jumlahItem,
      pembayaranTunai: data.pembayaranTunai.present
          ? data.pembayaranTunai.value
          : this.pembayaranTunai,
      pembayaranQris: data.pembayaranQris.present
          ? data.pembayaranQris.value
          : this.pembayaranQris,
      pembayaranTransfer: data.pembayaranTransfer.present
          ? data.pembayaranTransfer.value
          : this.pembayaranTransfer,
      pembayaranLainnya: data.pembayaranLainnya.present
          ? data.pembayaranLainnya.value
          : this.pembayaranLainnya,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailySummary(')
          ..write('date: $date, ')
          ..write('omzet: $omzet, ')
          ..write('hpp: $hpp, ')
          ..write('labaKotor: $labaKotor, ')
          ..write('jumlahTransaksi: $jumlahTransaksi, ')
          ..write('jumlahItem: $jumlahItem, ')
          ..write('pembayaranTunai: $pembayaranTunai, ')
          ..write('pembayaranQris: $pembayaranQris, ')
          ..write('pembayaranTransfer: $pembayaranTransfer, ')
          ..write('pembayaranLainnya: $pembayaranLainnya, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      date,
      omzet,
      hpp,
      labaKotor,
      jumlahTransaksi,
      jumlahItem,
      pembayaranTunai,
      pembayaranQris,
      pembayaranTransfer,
      pembayaranLainnya,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailySummary &&
          other.date == this.date &&
          other.omzet == this.omzet &&
          other.hpp == this.hpp &&
          other.labaKotor == this.labaKotor &&
          other.jumlahTransaksi == this.jumlahTransaksi &&
          other.jumlahItem == this.jumlahItem &&
          other.pembayaranTunai == this.pembayaranTunai &&
          other.pembayaranQris == this.pembayaranQris &&
          other.pembayaranTransfer == this.pembayaranTransfer &&
          other.pembayaranLainnya == this.pembayaranLainnya &&
          other.updatedAt == this.updatedAt);
}

class DailySummariesCompanion extends UpdateCompanion<DailySummary> {
  final Value<String> date;
  final Value<int> omzet;
  final Value<int> hpp;
  final Value<int> labaKotor;
  final Value<int> jumlahTransaksi;
  final Value<int> jumlahItem;
  final Value<int> pembayaranTunai;
  final Value<int> pembayaranQris;
  final Value<int> pembayaranTransfer;
  final Value<int> pembayaranLainnya;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DailySummariesCompanion({
    this.date = const Value.absent(),
    this.omzet = const Value.absent(),
    this.hpp = const Value.absent(),
    this.labaKotor = const Value.absent(),
    this.jumlahTransaksi = const Value.absent(),
    this.jumlahItem = const Value.absent(),
    this.pembayaranTunai = const Value.absent(),
    this.pembayaranQris = const Value.absent(),
    this.pembayaranTransfer = const Value.absent(),
    this.pembayaranLainnya = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailySummariesCompanion.insert({
    required String date,
    this.omzet = const Value.absent(),
    this.hpp = const Value.absent(),
    this.labaKotor = const Value.absent(),
    this.jumlahTransaksi = const Value.absent(),
    this.jumlahItem = const Value.absent(),
    this.pembayaranTunai = const Value.absent(),
    this.pembayaranQris = const Value.absent(),
    this.pembayaranTransfer = const Value.absent(),
    this.pembayaranLainnya = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailySummary> custom({
    Expression<String>? date,
    Expression<int>? omzet,
    Expression<int>? hpp,
    Expression<int>? labaKotor,
    Expression<int>? jumlahTransaksi,
    Expression<int>? jumlahItem,
    Expression<int>? pembayaranTunai,
    Expression<int>? pembayaranQris,
    Expression<int>? pembayaranTransfer,
    Expression<int>? pembayaranLainnya,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (omzet != null) 'omzet': omzet,
      if (hpp != null) 'hpp': hpp,
      if (labaKotor != null) 'laba_kotor': labaKotor,
      if (jumlahTransaksi != null) 'jumlah_transaksi': jumlahTransaksi,
      if (jumlahItem != null) 'jumlah_item': jumlahItem,
      if (pembayaranTunai != null) 'pembayaran_tunai': pembayaranTunai,
      if (pembayaranQris != null) 'pembayaran_qris': pembayaranQris,
      if (pembayaranTransfer != null) 'pembayaran_transfer': pembayaranTransfer,
      if (pembayaranLainnya != null) 'pembayaran_lainnya': pembayaranLainnya,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailySummariesCompanion copyWith(
      {Value<String>? date,
      Value<int>? omzet,
      Value<int>? hpp,
      Value<int>? labaKotor,
      Value<int>? jumlahTransaksi,
      Value<int>? jumlahItem,
      Value<int>? pembayaranTunai,
      Value<int>? pembayaranQris,
      Value<int>? pembayaranTransfer,
      Value<int>? pembayaranLainnya,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return DailySummariesCompanion(
      date: date ?? this.date,
      omzet: omzet ?? this.omzet,
      hpp: hpp ?? this.hpp,
      labaKotor: labaKotor ?? this.labaKotor,
      jumlahTransaksi: jumlahTransaksi ?? this.jumlahTransaksi,
      jumlahItem: jumlahItem ?? this.jumlahItem,
      pembayaranTunai: pembayaranTunai ?? this.pembayaranTunai,
      pembayaranQris: pembayaranQris ?? this.pembayaranQris,
      pembayaranTransfer: pembayaranTransfer ?? this.pembayaranTransfer,
      pembayaranLainnya: pembayaranLainnya ?? this.pembayaranLainnya,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (omzet.present) {
      map['omzet'] = Variable<int>(omzet.value);
    }
    if (hpp.present) {
      map['hpp'] = Variable<int>(hpp.value);
    }
    if (labaKotor.present) {
      map['laba_kotor'] = Variable<int>(labaKotor.value);
    }
    if (jumlahTransaksi.present) {
      map['jumlah_transaksi'] = Variable<int>(jumlahTransaksi.value);
    }
    if (jumlahItem.present) {
      map['jumlah_item'] = Variable<int>(jumlahItem.value);
    }
    if (pembayaranTunai.present) {
      map['pembayaran_tunai'] = Variable<int>(pembayaranTunai.value);
    }
    if (pembayaranQris.present) {
      map['pembayaran_qris'] = Variable<int>(pembayaranQris.value);
    }
    if (pembayaranTransfer.present) {
      map['pembayaran_transfer'] = Variable<int>(pembayaranTransfer.value);
    }
    if (pembayaranLainnya.present) {
      map['pembayaran_lainnya'] = Variable<int>(pembayaranLainnya.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailySummariesCompanion(')
          ..write('date: $date, ')
          ..write('omzet: $omzet, ')
          ..write('hpp: $hpp, ')
          ..write('labaKotor: $labaKotor, ')
          ..write('jumlahTransaksi: $jumlahTransaksi, ')
          ..write('jumlahItem: $jumlahItem, ')
          ..write('pembayaranTunai: $pembayaranTunai, ')
          ..write('pembayaranQris: $pembayaranQris, ')
          ..write('pembayaranTransfer: $pembayaranTransfer, ')
          ..write('pembayaranLainnya: $pembayaranLainnya, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EmployeesTable extends Employees
    with TableInfo<$EmployeesTable, Employee> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmployeesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, isActive, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'employees';
  @override
  VerificationContext validateIntegrity(Insertable<Employee> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Employee map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Employee(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $EmployeesTable createAlias(String alias) {
    return $EmployeesTable(attachedDatabase, alias);
  }
}

class Employee extends DataClass implements Insertable<Employee> {
  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Employee(
      {required this.id,
      required this.name,
      required this.isActive,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EmployeesCompanion toCompanion(bool nullToAbsent) {
    return EmployeesCompanion(
      id: Value(id),
      name: Value(name),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Employee.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Employee(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Employee copyWith(
          {String? id,
          String? name,
          bool? isActive,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Employee(
        id: id ?? this.id,
        name: name ?? this.name,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Employee copyWithCompanion(EmployeesCompanion data) {
    return Employee(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Employee(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isActive, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Employee &&
          other.id == this.id &&
          other.name == this.name &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EmployeesCompanion extends UpdateCompanion<Employee> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EmployeesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmployeesCompanion.insert({
    required String id,
    required String name,
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<Employee> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmployeesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return EmployeesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmployeesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CashClosingsTable extends CashClosings
    with TableInfo<$CashClosingsTable, CashClosing> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashClosingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceCodeMeta =
      const VerificationMeta('deviceCode');
  @override
  late final GeneratedColumn<String> deviceCode = GeneratedColumn<String>(
      'device_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _systemCashMeta =
      const VerificationMeta('systemCash');
  @override
  late final GeneratedColumn<int> systemCash = GeneratedColumn<int>(
      'system_cash', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _systemNonCashMeta =
      const VerificationMeta('systemNonCash');
  @override
  late final GeneratedColumn<int> systemNonCash = GeneratedColumn<int>(
      'system_non_cash', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _txCountMeta =
      const VerificationMeta('txCount');
  @override
  late final GeneratedColumn<int> txCount = GeneratedColumn<int>(
      'tx_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _physicalCashMeta =
      const VerificationMeta('physicalCash');
  @override
  late final GeneratedColumn<int> physicalCash = GeneratedColumn<int>(
      'physical_cash', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _differenceMeta =
      const VerificationMeta('difference');
  @override
  late final GeneratedColumn<int> difference = GeneratedColumn<int>(
      'difference', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        date,
        deviceCode,
        systemCash,
        systemNonCash,
        txCount,
        physicalCash,
        difference,
        note,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_closings';
  @override
  VerificationContext validateIntegrity(Insertable<CashClosing> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('device_code')) {
      context.handle(
          _deviceCodeMeta,
          deviceCode.isAcceptableOrUnknown(
              data['device_code']!, _deviceCodeMeta));
    }
    if (data.containsKey('system_cash')) {
      context.handle(
          _systemCashMeta,
          systemCash.isAcceptableOrUnknown(
              data['system_cash']!, _systemCashMeta));
    } else if (isInserting) {
      context.missing(_systemCashMeta);
    }
    if (data.containsKey('system_non_cash')) {
      context.handle(
          _systemNonCashMeta,
          systemNonCash.isAcceptableOrUnknown(
              data['system_non_cash']!, _systemNonCashMeta));
    }
    if (data.containsKey('tx_count')) {
      context.handle(_txCountMeta,
          txCount.isAcceptableOrUnknown(data['tx_count']!, _txCountMeta));
    }
    if (data.containsKey('physical_cash')) {
      context.handle(
          _physicalCashMeta,
          physicalCash.isAcceptableOrUnknown(
              data['physical_cash']!, _physicalCashMeta));
    } else if (isInserting) {
      context.missing(_physicalCashMeta);
    }
    if (data.containsKey('difference')) {
      context.handle(
          _differenceMeta,
          difference.isAcceptableOrUnknown(
              data['difference']!, _differenceMeta));
    } else if (isInserting) {
      context.missing(_differenceMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {date, deviceCode},
      ];
  @override
  CashClosing map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashClosing(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      deviceCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_code']),
      systemCash: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}system_cash'])!,
      systemNonCash: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}system_non_cash'])!,
      txCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tx_count'])!,
      physicalCash: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}physical_cash'])!,
      difference: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}difference'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CashClosingsTable createAlias(String alias) {
    return $CashClosingsTable(attachedDatabase, alias);
  }
}

class CashClosing extends DataClass implements Insertable<CashClosing> {
  final String id;
  final String date;
  final String? deviceCode;

  /// Kas tunai yang diharapkan (dari penjualan tunai hari itu).
  final int systemCash;

  /// Total non-tunai (transfer/QRIS/dll) — informasi, tidak masuk selisih laci.
  final int systemNonCash;
  final int txCount;

  /// Uang fisik yang dihitung di laci.
  final int physicalCash;

  /// physicalCash − systemCash (positif = lebih, negatif = kurang).
  final int difference;
  final String? note;
  final DateTime createdAt;
  const CashClosing(
      {required this.id,
      required this.date,
      this.deviceCode,
      required this.systemCash,
      required this.systemNonCash,
      required this.txCount,
      required this.physicalCash,
      required this.difference,
      this.note,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || deviceCode != null) {
      map['device_code'] = Variable<String>(deviceCode);
    }
    map['system_cash'] = Variable<int>(systemCash);
    map['system_non_cash'] = Variable<int>(systemNonCash);
    map['tx_count'] = Variable<int>(txCount);
    map['physical_cash'] = Variable<int>(physicalCash);
    map['difference'] = Variable<int>(difference);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CashClosingsCompanion toCompanion(bool nullToAbsent) {
    return CashClosingsCompanion(
      id: Value(id),
      date: Value(date),
      deviceCode: deviceCode == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceCode),
      systemCash: Value(systemCash),
      systemNonCash: Value(systemNonCash),
      txCount: Value(txCount),
      physicalCash: Value(physicalCash),
      difference: Value(difference),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory CashClosing.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashClosing(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      deviceCode: serializer.fromJson<String?>(json['deviceCode']),
      systemCash: serializer.fromJson<int>(json['systemCash']),
      systemNonCash: serializer.fromJson<int>(json['systemNonCash']),
      txCount: serializer.fromJson<int>(json['txCount']),
      physicalCash: serializer.fromJson<int>(json['physicalCash']),
      difference: serializer.fromJson<int>(json['difference']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'deviceCode': serializer.toJson<String?>(deviceCode),
      'systemCash': serializer.toJson<int>(systemCash),
      'systemNonCash': serializer.toJson<int>(systemNonCash),
      'txCount': serializer.toJson<int>(txCount),
      'physicalCash': serializer.toJson<int>(physicalCash),
      'difference': serializer.toJson<int>(difference),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CashClosing copyWith(
          {String? id,
          String? date,
          Value<String?> deviceCode = const Value.absent(),
          int? systemCash,
          int? systemNonCash,
          int? txCount,
          int? physicalCash,
          int? difference,
          Value<String?> note = const Value.absent(),
          DateTime? createdAt}) =>
      CashClosing(
        id: id ?? this.id,
        date: date ?? this.date,
        deviceCode: deviceCode.present ? deviceCode.value : this.deviceCode,
        systemCash: systemCash ?? this.systemCash,
        systemNonCash: systemNonCash ?? this.systemNonCash,
        txCount: txCount ?? this.txCount,
        physicalCash: physicalCash ?? this.physicalCash,
        difference: difference ?? this.difference,
        note: note.present ? note.value : this.note,
        createdAt: createdAt ?? this.createdAt,
      );
  CashClosing copyWithCompanion(CashClosingsCompanion data) {
    return CashClosing(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      deviceCode:
          data.deviceCode.present ? data.deviceCode.value : this.deviceCode,
      systemCash:
          data.systemCash.present ? data.systemCash.value : this.systemCash,
      systemNonCash: data.systemNonCash.present
          ? data.systemNonCash.value
          : this.systemNonCash,
      txCount: data.txCount.present ? data.txCount.value : this.txCount,
      physicalCash: data.physicalCash.present
          ? data.physicalCash.value
          : this.physicalCash,
      difference:
          data.difference.present ? data.difference.value : this.difference,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashClosing(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('deviceCode: $deviceCode, ')
          ..write('systemCash: $systemCash, ')
          ..write('systemNonCash: $systemNonCash, ')
          ..write('txCount: $txCount, ')
          ..write('physicalCash: $physicalCash, ')
          ..write('difference: $difference, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, date, deviceCode, systemCash,
      systemNonCash, txCount, physicalCash, difference, note, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashClosing &&
          other.id == this.id &&
          other.date == this.date &&
          other.deviceCode == this.deviceCode &&
          other.systemCash == this.systemCash &&
          other.systemNonCash == this.systemNonCash &&
          other.txCount == this.txCount &&
          other.physicalCash == this.physicalCash &&
          other.difference == this.difference &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class CashClosingsCompanion extends UpdateCompanion<CashClosing> {
  final Value<String> id;
  final Value<String> date;
  final Value<String?> deviceCode;
  final Value<int> systemCash;
  final Value<int> systemNonCash;
  final Value<int> txCount;
  final Value<int> physicalCash;
  final Value<int> difference;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CashClosingsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.deviceCode = const Value.absent(),
    this.systemCash = const Value.absent(),
    this.systemNonCash = const Value.absent(),
    this.txCount = const Value.absent(),
    this.physicalCash = const Value.absent(),
    this.difference = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CashClosingsCompanion.insert({
    required String id,
    required String date,
    this.deviceCode = const Value.absent(),
    required int systemCash,
    this.systemNonCash = const Value.absent(),
    this.txCount = const Value.absent(),
    required int physicalCash,
    required int difference,
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        date = Value(date),
        systemCash = Value(systemCash),
        physicalCash = Value(physicalCash),
        difference = Value(difference);
  static Insertable<CashClosing> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? deviceCode,
    Expression<int>? systemCash,
    Expression<int>? systemNonCash,
    Expression<int>? txCount,
    Expression<int>? physicalCash,
    Expression<int>? difference,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (deviceCode != null) 'device_code': deviceCode,
      if (systemCash != null) 'system_cash': systemCash,
      if (systemNonCash != null) 'system_non_cash': systemNonCash,
      if (txCount != null) 'tx_count': txCount,
      if (physicalCash != null) 'physical_cash': physicalCash,
      if (difference != null) 'difference': difference,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CashClosingsCompanion copyWith(
      {Value<String>? id,
      Value<String>? date,
      Value<String?>? deviceCode,
      Value<int>? systemCash,
      Value<int>? systemNonCash,
      Value<int>? txCount,
      Value<int>? physicalCash,
      Value<int>? difference,
      Value<String?>? note,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return CashClosingsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      deviceCode: deviceCode ?? this.deviceCode,
      systemCash: systemCash ?? this.systemCash,
      systemNonCash: systemNonCash ?? this.systemNonCash,
      txCount: txCount ?? this.txCount,
      physicalCash: physicalCash ?? this.physicalCash,
      difference: difference ?? this.difference,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (deviceCode.present) {
      map['device_code'] = Variable<String>(deviceCode.value);
    }
    if (systemCash.present) {
      map['system_cash'] = Variable<int>(systemCash.value);
    }
    if (systemNonCash.present) {
      map['system_non_cash'] = Variable<int>(systemNonCash.value);
    }
    if (txCount.present) {
      map['tx_count'] = Variable<int>(txCount.value);
    }
    if (physicalCash.present) {
      map['physical_cash'] = Variable<int>(physicalCash.value);
    }
    if (difference.present) {
      map['difference'] = Variable<int>(difference.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashClosingsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('deviceCode: $deviceCode, ')
          ..write('systemCash: $systemCash, ')
          ..write('systemNonCash: $systemNonCash, ')
          ..write('txCount: $txCount, ')
          ..write('physicalCash: $physicalCash, ')
          ..write('difference: $difference, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncUploadQueueTable extends SyncUploadQueue
    with TableInfo<$SyncUploadQueueTable, SyncUploadQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncUploadQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fromIpMeta =
      const VerificationMeta('fromIp');
  @override
  late final GeneratedColumn<String> fromIp = GeneratedColumn<String>(
      'from_ip', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _arrivedAtMeta =
      const VerificationMeta('arrivedAt');
  @override
  late final GeneratedColumn<DateTime> arrivedAt = GeneratedColumn<DateTime>(
      'arrived_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _tablesJsonMeta =
      const VerificationMeta('tablesJson');
  @override
  late final GeneratedColumn<String> tablesJson = GeneratedColumn<String>(
      'tables_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sinceMeta = const VerificationMeta('since');
  @override
  late final GeneratedColumn<DateTime> since = GeneratedColumn<DateTime>(
      'since', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _tablesSummaryMeta =
      const VerificationMeta('tablesSummary');
  @override
  late final GeneratedColumn<String> tablesSummary = GeneratedColumn<String>(
      'tables_summary', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, fromIp, arrivedAt, tablesJson, since, tablesSummary];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_upload_queue';
  @override
  VerificationContext validateIntegrity(
      Insertable<SyncUploadQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_ip')) {
      context.handle(_fromIpMeta,
          fromIp.isAcceptableOrUnknown(data['from_ip']!, _fromIpMeta));
    } else if (isInserting) {
      context.missing(_fromIpMeta);
    }
    if (data.containsKey('arrived_at')) {
      context.handle(_arrivedAtMeta,
          arrivedAt.isAcceptableOrUnknown(data['arrived_at']!, _arrivedAtMeta));
    }
    if (data.containsKey('tables_json')) {
      context.handle(
          _tablesJsonMeta,
          tablesJson.isAcceptableOrUnknown(
              data['tables_json']!, _tablesJsonMeta));
    } else if (isInserting) {
      context.missing(_tablesJsonMeta);
    }
    if (data.containsKey('since')) {
      context.handle(
          _sinceMeta, since.isAcceptableOrUnknown(data['since']!, _sinceMeta));
    } else if (isInserting) {
      context.missing(_sinceMeta);
    }
    if (data.containsKey('tables_summary')) {
      context.handle(
          _tablesSummaryMeta,
          tablesSummary.isAcceptableOrUnknown(
              data['tables_summary']!, _tablesSummaryMeta));
    } else if (isInserting) {
      context.missing(_tablesSummaryMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncUploadQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncUploadQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      fromIp: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}from_ip'])!,
      arrivedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}arrived_at'])!,
      tablesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tables_json'])!,
      since: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}since'])!,
      tablesSummary: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tables_summary'])!,
    );
  }

  @override
  $SyncUploadQueueTable createAlias(String alias) {
    return $SyncUploadQueueTable(attachedDatabase, alias);
  }
}

class SyncUploadQueueData extends DataClass
    implements Insertable<SyncUploadQueueData> {
  final String id;
  final String fromIp;
  final DateTime arrivedAt;
  final String tablesJson;
  final DateTime since;
  final String tablesSummary;
  const SyncUploadQueueData(
      {required this.id,
      required this.fromIp,
      required this.arrivedAt,
      required this.tablesJson,
      required this.since,
      required this.tablesSummary});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_ip'] = Variable<String>(fromIp);
    map['arrived_at'] = Variable<DateTime>(arrivedAt);
    map['tables_json'] = Variable<String>(tablesJson);
    map['since'] = Variable<DateTime>(since);
    map['tables_summary'] = Variable<String>(tablesSummary);
    return map;
  }

  SyncUploadQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncUploadQueueCompanion(
      id: Value(id),
      fromIp: Value(fromIp),
      arrivedAt: Value(arrivedAt),
      tablesJson: Value(tablesJson),
      since: Value(since),
      tablesSummary: Value(tablesSummary),
    );
  }

  factory SyncUploadQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncUploadQueueData(
      id: serializer.fromJson<String>(json['id']),
      fromIp: serializer.fromJson<String>(json['fromIp']),
      arrivedAt: serializer.fromJson<DateTime>(json['arrivedAt']),
      tablesJson: serializer.fromJson<String>(json['tablesJson']),
      since: serializer.fromJson<DateTime>(json['since']),
      tablesSummary: serializer.fromJson<String>(json['tablesSummary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromIp': serializer.toJson<String>(fromIp),
      'arrivedAt': serializer.toJson<DateTime>(arrivedAt),
      'tablesJson': serializer.toJson<String>(tablesJson),
      'since': serializer.toJson<DateTime>(since),
      'tablesSummary': serializer.toJson<String>(tablesSummary),
    };
  }

  SyncUploadQueueData copyWith(
          {String? id,
          String? fromIp,
          DateTime? arrivedAt,
          String? tablesJson,
          DateTime? since,
          String? tablesSummary}) =>
      SyncUploadQueueData(
        id: id ?? this.id,
        fromIp: fromIp ?? this.fromIp,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        tablesJson: tablesJson ?? this.tablesJson,
        since: since ?? this.since,
        tablesSummary: tablesSummary ?? this.tablesSummary,
      );
  SyncUploadQueueData copyWithCompanion(SyncUploadQueueCompanion data) {
    return SyncUploadQueueData(
      id: data.id.present ? data.id.value : this.id,
      fromIp: data.fromIp.present ? data.fromIp.value : this.fromIp,
      arrivedAt: data.arrivedAt.present ? data.arrivedAt.value : this.arrivedAt,
      tablesJson:
          data.tablesJson.present ? data.tablesJson.value : this.tablesJson,
      since: data.since.present ? data.since.value : this.since,
      tablesSummary: data.tablesSummary.present
          ? data.tablesSummary.value
          : this.tablesSummary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncUploadQueueData(')
          ..write('id: $id, ')
          ..write('fromIp: $fromIp, ')
          ..write('arrivedAt: $arrivedAt, ')
          ..write('tablesJson: $tablesJson, ')
          ..write('since: $since, ')
          ..write('tablesSummary: $tablesSummary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, fromIp, arrivedAt, tablesJson, since, tablesSummary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncUploadQueueData &&
          other.id == this.id &&
          other.fromIp == this.fromIp &&
          other.arrivedAt == this.arrivedAt &&
          other.tablesJson == this.tablesJson &&
          other.since == this.since &&
          other.tablesSummary == this.tablesSummary);
}

class SyncUploadQueueCompanion extends UpdateCompanion<SyncUploadQueueData> {
  final Value<String> id;
  final Value<String> fromIp;
  final Value<DateTime> arrivedAt;
  final Value<String> tablesJson;
  final Value<DateTime> since;
  final Value<String> tablesSummary;
  final Value<int> rowid;
  const SyncUploadQueueCompanion({
    this.id = const Value.absent(),
    this.fromIp = const Value.absent(),
    this.arrivedAt = const Value.absent(),
    this.tablesJson = const Value.absent(),
    this.since = const Value.absent(),
    this.tablesSummary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncUploadQueueCompanion.insert({
    required String id,
    required String fromIp,
    this.arrivedAt = const Value.absent(),
    required String tablesJson,
    required DateTime since,
    required String tablesSummary,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        fromIp = Value(fromIp),
        tablesJson = Value(tablesJson),
        since = Value(since),
        tablesSummary = Value(tablesSummary);
  static Insertable<SyncUploadQueueData> custom({
    Expression<String>? id,
    Expression<String>? fromIp,
    Expression<DateTime>? arrivedAt,
    Expression<String>? tablesJson,
    Expression<DateTime>? since,
    Expression<String>? tablesSummary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromIp != null) 'from_ip': fromIp,
      if (arrivedAt != null) 'arrived_at': arrivedAt,
      if (tablesJson != null) 'tables_json': tablesJson,
      if (since != null) 'since': since,
      if (tablesSummary != null) 'tables_summary': tablesSummary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncUploadQueueCompanion copyWith(
      {Value<String>? id,
      Value<String>? fromIp,
      Value<DateTime>? arrivedAt,
      Value<String>? tablesJson,
      Value<DateTime>? since,
      Value<String>? tablesSummary,
      Value<int>? rowid}) {
    return SyncUploadQueueCompanion(
      id: id ?? this.id,
      fromIp: fromIp ?? this.fromIp,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      tablesJson: tablesJson ?? this.tablesJson,
      since: since ?? this.since,
      tablesSummary: tablesSummary ?? this.tablesSummary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromIp.present) {
      map['from_ip'] = Variable<String>(fromIp.value);
    }
    if (arrivedAt.present) {
      map['arrived_at'] = Variable<DateTime>(arrivedAt.value);
    }
    if (tablesJson.present) {
      map['tables_json'] = Variable<String>(tablesJson.value);
    }
    if (since.present) {
      map['since'] = Variable<DateTime>(since.value);
    }
    if (tablesSummary.present) {
      map['tables_summary'] = Variable<String>(tablesSummary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncUploadQueueCompanion(')
          ..write('id: $id, ')
          ..write('fromIp: $fromIp, ')
          ..write('arrivedAt: $arrivedAt, ')
          ..write('tablesJson: $tablesJson, ')
          ..write('since: $since, ')
          ..write('tablesSummary: $tablesSummary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $ProductGroupsTable productGroups = $ProductGroupsTable(this);
  late final $UnitTypesTable unitTypes = $UnitTypesTable(this);
  late final $ProductUnitsTable productUnits = $ProductUnitsTable(this);
  late final $ProductBarcodesTable productBarcodes =
      $ProductBarcodesTable(this);
  late final $PriceTiersTable priceTiers = $PriceTiersTable(this);
  late final $AltPricesTable altPrices = $AltPricesTable(this);
  late final $CustomerGroupsTable customerGroups = $CustomerGroupsTable(this);
  late final $CustomerGroupPricesTable customerGroupPrices =
      $CustomerGroupPricesTable(this);
  late final $CustomersTable customers = $CustomersTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $TransactionItemsTable transactionItems =
      $TransactionItemsTable(this);
  late final $TransactionPaymentsTable transactionPayments =
      $TransactionPaymentsTable(this);
  late final $HeldOrdersTable heldOrders = $HeldOrdersTable(this);
  late final $StockLedgerTable stockLedger = $StockLedgerTable(this);
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $LoyaltyPointLedgerTable loyaltyPointLedger =
      $LoyaltyPointLedgerTable(this);
  late final $SuppliersTable suppliers = $SuppliersTable(this);
  late final $PurchasesTable purchases = $PurchasesTable(this);
  late final $PurchaseItemsTable purchaseItems = $PurchaseItemsTable(this);
  late final $KasirPermissionsTable kasirPermissions =
      $KasirPermissionsTable(this);
  late final $PaymentMethodsTable paymentMethods = $PaymentMethodsTable(this);
  late final $DailySummariesTable dailySummaries = $DailySummariesTable(this);
  late final $EmployeesTable employees = $EmployeesTable(this);
  late final $CashClosingsTable cashClosings = $CashClosingsTable(this);
  late final $SyncUploadQueueTable syncUploadQueue =
      $SyncUploadQueueTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        appSettings,
        products,
        productGroups,
        unitTypes,
        productUnits,
        productBarcodes,
        priceTiers,
        altPrices,
        customerGroups,
        customerGroupPrices,
        customers,
        transactions,
        transactionItems,
        transactionPayments,
        heldOrders,
        stockLedger,
        expenses,
        loyaltyPointLedger,
        suppliers,
        purchases,
        purchaseItems,
        kasirPermissions,
        paymentMethods,
        dailySummaries,
        employees,
        cashClosings,
        syncUploadQueue
      ];
}

typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  required String key,
  required String value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (AppSetting, BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>),
    AppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (AppSetting, BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>),
    AppSetting,
    PrefetchHooks Function()>;
typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
  required String id,
  required String name,
  Value<int?> productGroupId,
  Value<String?> kodeProduk,
  Value<String?> parentProductId,
  Value<bool> isActive,
  Value<bool> markedOutOfStock,
  Value<bool> locallyModified,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int?> productGroupId,
  Value<String?> kodeProduk,
  Value<String?> parentProductId,
  Value<bool> isActive,
  Value<bool> markedOutOfStock,
  Value<bool> locallyModified,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$ProductsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductsTable, Product> {
  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProductUnitsTable, List<ProductUnit>>
      _productUnitsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.productUnits,
          aliasName:
              $_aliasNameGenerator(db.products.id, db.productUnits.productId));

  $$ProductUnitsTableProcessedTableManager get productUnitsRefs {
    final manager = $$ProductUnitsTableTableManager($_db, $_db.productUnits)
        .filter((f) => f.productId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_productUnitsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get productGroupId => $composableBuilder(
      column: $table.productGroupId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kodeProduk => $composableBuilder(
      column: $table.kodeProduk, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentProductId => $composableBuilder(
      column: $table.parentProductId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get markedOutOfStock => $composableBuilder(
      column: $table.markedOutOfStock,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get locallyModified => $composableBuilder(
      column: $table.locallyModified,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> productUnitsRefs(
      Expression<bool> Function($$ProductUnitsTableFilterComposer f) f) {
    final $$ProductUnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableFilterComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get productGroupId => $composableBuilder(
      column: $table.productGroupId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kodeProduk => $composableBuilder(
      column: $table.kodeProduk, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentProductId => $composableBuilder(
      column: $table.parentProductId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get markedOutOfStock => $composableBuilder(
      column: $table.markedOutOfStock,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get locallyModified => $composableBuilder(
      column: $table.locallyModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get productGroupId => $composableBuilder(
      column: $table.productGroupId, builder: (column) => column);

  GeneratedColumn<String> get kodeProduk => $composableBuilder(
      column: $table.kodeProduk, builder: (column) => column);

  GeneratedColumn<String> get parentProductId => $composableBuilder(
      column: $table.parentProductId, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get markedOutOfStock => $composableBuilder(
      column: $table.markedOutOfStock, builder: (column) => column);

  GeneratedColumn<bool> get locallyModified => $composableBuilder(
      column: $table.locallyModified, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> productUnitsRefs<T extends Object>(
      Expression<T> Function($$ProductUnitsTableAnnotationComposer a) f) {
    final $$ProductUnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, $$ProductsTableReferences),
    Product,
    PrefetchHooks Function({bool productUnitsRefs})> {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int?> productGroupId = const Value.absent(),
            Value<String?> kodeProduk = const Value.absent(),
            Value<String?> parentProductId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> markedOutOfStock = const Value.absent(),
            Value<bool> locallyModified = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion(
            id: id,
            name: name,
            productGroupId: productGroupId,
            kodeProduk: kodeProduk,
            parentProductId: parentProductId,
            isActive: isActive,
            markedOutOfStock: markedOutOfStock,
            locallyModified: locallyModified,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<int?> productGroupId = const Value.absent(),
            Value<String?> kodeProduk = const Value.absent(),
            Value<String?> parentProductId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> markedOutOfStock = const Value.absent(),
            Value<bool> locallyModified = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion.insert(
            id: id,
            name: name,
            productGroupId: productGroupId,
            kodeProduk: kodeProduk,
            parentProductId: parentProductId,
            isActive: isActive,
            markedOutOfStock: markedOutOfStock,
            locallyModified: locallyModified,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ProductsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({productUnitsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (productUnitsRefs) db.productUnits],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productUnitsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ProductsTableReferences
                            ._productUnitsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .productUnitsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProductsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, $$ProductsTableReferences),
    Product,
    PrefetchHooks Function({bool productUnitsRefs})>;
typedef $$ProductGroupsTableCreateCompanionBuilder = ProductGroupsCompanion
    Function({
  Value<int> id,
  Value<String?> name,
});
typedef $$ProductGroupsTableUpdateCompanionBuilder = ProductGroupsCompanion
    Function({
  Value<int> id,
  Value<String?> name,
});

class $$ProductGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductGroupsTable> {
  $$ProductGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));
}

class $$ProductGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductGroupsTable> {
  $$ProductGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));
}

class $$ProductGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductGroupsTable> {
  $$ProductGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$ProductGroupsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductGroupsTable,
    ProductGroup,
    $$ProductGroupsTableFilterComposer,
    $$ProductGroupsTableOrderingComposer,
    $$ProductGroupsTableAnnotationComposer,
    $$ProductGroupsTableCreateCompanionBuilder,
    $$ProductGroupsTableUpdateCompanionBuilder,
    (
      ProductGroup,
      BaseReferences<_$AppDatabase, $ProductGroupsTable, ProductGroup>
    ),
    ProductGroup,
    PrefetchHooks Function()> {
  $$ProductGroupsTableTableManager(_$AppDatabase db, $ProductGroupsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> name = const Value.absent(),
          }) =>
              ProductGroupsCompanion(
            id: id,
            name: name,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> name = const Value.absent(),
          }) =>
              ProductGroupsCompanion.insert(
            id: id,
            name: name,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProductGroupsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductGroupsTable,
    ProductGroup,
    $$ProductGroupsTableFilterComposer,
    $$ProductGroupsTableOrderingComposer,
    $$ProductGroupsTableAnnotationComposer,
    $$ProductGroupsTableCreateCompanionBuilder,
    $$ProductGroupsTableUpdateCompanionBuilder,
    (
      ProductGroup,
      BaseReferences<_$AppDatabase, $ProductGroupsTable, ProductGroup>
    ),
    ProductGroup,
    PrefetchHooks Function()>;
typedef $$UnitTypesTableCreateCompanionBuilder = UnitTypesCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> abbrev,
});
typedef $$UnitTypesTableUpdateCompanionBuilder = UnitTypesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> abbrev,
});

class $$UnitTypesTableFilterComposer
    extends Composer<_$AppDatabase, $UnitTypesTable> {
  $$UnitTypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get abbrev => $composableBuilder(
      column: $table.abbrev, builder: (column) => ColumnFilters(column));
}

class $$UnitTypesTableOrderingComposer
    extends Composer<_$AppDatabase, $UnitTypesTable> {
  $$UnitTypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get abbrev => $composableBuilder(
      column: $table.abbrev, builder: (column) => ColumnOrderings(column));
}

class $$UnitTypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UnitTypesTable> {
  $$UnitTypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get abbrev =>
      $composableBuilder(column: $table.abbrev, builder: (column) => column);
}

class $$UnitTypesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UnitTypesTable,
    UnitType,
    $$UnitTypesTableFilterComposer,
    $$UnitTypesTableOrderingComposer,
    $$UnitTypesTableAnnotationComposer,
    $$UnitTypesTableCreateCompanionBuilder,
    $$UnitTypesTableUpdateCompanionBuilder,
    (UnitType, BaseReferences<_$AppDatabase, $UnitTypesTable, UnitType>),
    UnitType,
    PrefetchHooks Function()> {
  $$UnitTypesTableTableManager(_$AppDatabase db, $UnitTypesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnitTypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UnitTypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UnitTypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> abbrev = const Value.absent(),
          }) =>
              UnitTypesCompanion(
            id: id,
            name: name,
            abbrev: abbrev,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> abbrev = const Value.absent(),
          }) =>
              UnitTypesCompanion.insert(
            id: id,
            name: name,
            abbrev: abbrev,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UnitTypesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UnitTypesTable,
    UnitType,
    $$UnitTypesTableFilterComposer,
    $$UnitTypesTableOrderingComposer,
    $$UnitTypesTableAnnotationComposer,
    $$UnitTypesTableCreateCompanionBuilder,
    $$UnitTypesTableUpdateCompanionBuilder,
    (UnitType, BaseReferences<_$AppDatabase, $UnitTypesTable, UnitType>),
    UnitType,
    PrefetchHooks Function()>;
typedef $$ProductUnitsTableCreateCompanionBuilder = ProductUnitsCompanion
    Function({
  required String id,
  required String productId,
  Value<int?> unitTypeId,
  Value<bool> isBaseUnit,
  Value<double> ratioToBase,
  Value<bool> isNonStock,
  Value<int?> minStock,
  Value<int> rowid,
});
typedef $$ProductUnitsTableUpdateCompanionBuilder = ProductUnitsCompanion
    Function({
  Value<String> id,
  Value<String> productId,
  Value<int?> unitTypeId,
  Value<bool> isBaseUnit,
  Value<double> ratioToBase,
  Value<bool> isNonStock,
  Value<int?> minStock,
  Value<int> rowid,
});

final class $$ProductUnitsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductUnitsTable, ProductUnit> {
  $$ProductUnitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
          $_aliasNameGenerator(db.productUnits.productId, db.products.id));

  $$ProductsTableProcessedTableManager get productId {
    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id($_item.productId));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$ProductBarcodesTable, List<ProductBarcode>>
      _productBarcodesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.productBarcodes,
              aliasName: $_aliasNameGenerator(
                  db.productUnits.id, db.productBarcodes.productUnitId));

  $$ProductBarcodesTableProcessedTableManager get productBarcodesRefs {
    final manager =
        $$ProductBarcodesTableTableManager($_db, $_db.productBarcodes)
            .filter((f) => f.productUnitId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_productBarcodesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$PriceTiersTable, List<PriceTier>>
      _priceTiersRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.priceTiers,
              aliasName: $_aliasNameGenerator(
                  db.productUnits.id, db.priceTiers.productUnitId));

  $$PriceTiersTableProcessedTableManager get priceTiersRefs {
    final manager = $$PriceTiersTableTableManager($_db, $_db.priceTiers)
        .filter((f) => f.productUnitId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_priceTiersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$AltPricesTable, List<AltPrice>>
      _altPricesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.altPrices,
              aliasName: $_aliasNameGenerator(
                  db.productUnits.id, db.altPrices.productUnitId));

  $$AltPricesTableProcessedTableManager get altPricesRefs {
    final manager = $$AltPricesTableTableManager($_db, $_db.altPrices)
        .filter((f) => f.productUnitId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_altPricesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$CustomerGroupPricesTable,
      List<CustomerGroupPrice>> _customerGroupPricesRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.customerGroupPrices,
          aliasName: $_aliasNameGenerator(
              db.productUnits.id, db.customerGroupPrices.productUnitId));

  $$CustomerGroupPricesTableProcessedTableManager get customerGroupPricesRefs {
    final manager =
        $$CustomerGroupPricesTableTableManager($_db, $_db.customerGroupPrices)
            .filter((f) => f.productUnitId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_customerGroupPricesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProductUnitsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductUnitsTable> {
  $$ProductUnitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unitTypeId => $composableBuilder(
      column: $table.unitTypeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBaseUnit => $composableBuilder(
      column: $table.isBaseUnit, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get ratioToBase => $composableBuilder(
      column: $table.ratioToBase, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isNonStock => $composableBuilder(
      column: $table.isNonStock, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minStock => $composableBuilder(
      column: $table.minStock, builder: (column) => ColumnFilters(column));

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> productBarcodesRefs(
      Expression<bool> Function($$ProductBarcodesTableFilterComposer f) f) {
    final $$ProductBarcodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productBarcodes,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductBarcodesTableFilterComposer(
              $db: $db,
              $table: $db.productBarcodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> priceTiersRefs(
      Expression<bool> Function($$PriceTiersTableFilterComposer f) f) {
    final $$PriceTiersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.priceTiers,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PriceTiersTableFilterComposer(
              $db: $db,
              $table: $db.priceTiers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> altPricesRefs(
      Expression<bool> Function($$AltPricesTableFilterComposer f) f) {
    final $$AltPricesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.altPrices,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AltPricesTableFilterComposer(
              $db: $db,
              $table: $db.altPrices,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> customerGroupPricesRefs(
      Expression<bool> Function($$CustomerGroupPricesTableFilterComposer f) f) {
    final $$CustomerGroupPricesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.customerGroupPrices,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CustomerGroupPricesTableFilterComposer(
              $db: $db,
              $table: $db.customerGroupPrices,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductUnitsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductUnitsTable> {
  $$ProductUnitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unitTypeId => $composableBuilder(
      column: $table.unitTypeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBaseUnit => $composableBuilder(
      column: $table.isBaseUnit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get ratioToBase => $composableBuilder(
      column: $table.ratioToBase, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isNonStock => $composableBuilder(
      column: $table.isNonStock, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minStock => $composableBuilder(
      column: $table.minStock, builder: (column) => ColumnOrderings(column));

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductUnitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductUnitsTable> {
  $$ProductUnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get unitTypeId => $composableBuilder(
      column: $table.unitTypeId, builder: (column) => column);

  GeneratedColumn<bool> get isBaseUnit => $composableBuilder(
      column: $table.isBaseUnit, builder: (column) => column);

  GeneratedColumn<double> get ratioToBase => $composableBuilder(
      column: $table.ratioToBase, builder: (column) => column);

  GeneratedColumn<bool> get isNonStock => $composableBuilder(
      column: $table.isNonStock, builder: (column) => column);

  GeneratedColumn<int> get minStock =>
      $composableBuilder(column: $table.minStock, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> productBarcodesRefs<T extends Object>(
      Expression<T> Function($$ProductBarcodesTableAnnotationComposer a) f) {
    final $$ProductBarcodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productBarcodes,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductBarcodesTableAnnotationComposer(
              $db: $db,
              $table: $db.productBarcodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> priceTiersRefs<T extends Object>(
      Expression<T> Function($$PriceTiersTableAnnotationComposer a) f) {
    final $$PriceTiersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.priceTiers,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PriceTiersTableAnnotationComposer(
              $db: $db,
              $table: $db.priceTiers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> altPricesRefs<T extends Object>(
      Expression<T> Function($$AltPricesTableAnnotationComposer a) f) {
    final $$AltPricesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.altPrices,
        getReferencedColumn: (t) => t.productUnitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AltPricesTableAnnotationComposer(
              $db: $db,
              $table: $db.altPrices,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> customerGroupPricesRefs<T extends Object>(
      Expression<T> Function($$CustomerGroupPricesTableAnnotationComposer a)
          f) {
    final $$CustomerGroupPricesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.customerGroupPrices,
            getReferencedColumn: (t) => t.productUnitId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$CustomerGroupPricesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.customerGroupPrices,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$ProductUnitsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductUnitsTable,
    ProductUnit,
    $$ProductUnitsTableFilterComposer,
    $$ProductUnitsTableOrderingComposer,
    $$ProductUnitsTableAnnotationComposer,
    $$ProductUnitsTableCreateCompanionBuilder,
    $$ProductUnitsTableUpdateCompanionBuilder,
    (ProductUnit, $$ProductUnitsTableReferences),
    ProductUnit,
    PrefetchHooks Function(
        {bool productId,
        bool productBarcodesRefs,
        bool priceTiersRefs,
        bool altPricesRefs,
        bool customerGroupPricesRefs})> {
  $$ProductUnitsTableTableManager(_$AppDatabase db, $ProductUnitsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductUnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductUnitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductUnitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int?> unitTypeId = const Value.absent(),
            Value<bool> isBaseUnit = const Value.absent(),
            Value<double> ratioToBase = const Value.absent(),
            Value<bool> isNonStock = const Value.absent(),
            Value<int?> minStock = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductUnitsCompanion(
            id: id,
            productId: productId,
            unitTypeId: unitTypeId,
            isBaseUnit: isBaseUnit,
            ratioToBase: ratioToBase,
            isNonStock: isNonStock,
            minStock: minStock,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            Value<int?> unitTypeId = const Value.absent(),
            Value<bool> isBaseUnit = const Value.absent(),
            Value<double> ratioToBase = const Value.absent(),
            Value<bool> isNonStock = const Value.absent(),
            Value<int?> minStock = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductUnitsCompanion.insert(
            id: id,
            productId: productId,
            unitTypeId: unitTypeId,
            isBaseUnit: isBaseUnit,
            ratioToBase: ratioToBase,
            isNonStock: isNonStock,
            minStock: minStock,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductUnitsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {productId = false,
              productBarcodesRefs = false,
              priceTiersRefs = false,
              altPricesRefs = false,
              customerGroupPricesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (productBarcodesRefs) db.productBarcodes,
                if (priceTiersRefs) db.priceTiers,
                if (altPricesRefs) db.altPrices,
                if (customerGroupPricesRefs) db.customerGroupPrices
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$ProductUnitsTableReferences._productIdTable(db),
                    referencedColumn:
                        $$ProductUnitsTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productBarcodesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ProductUnitsTableReferences
                            ._productBarcodesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductUnitsTableReferences(db, table, p0)
                                .productBarcodesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productUnitId == item.id),
                        typedResults: items),
                  if (priceTiersRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ProductUnitsTableReferences
                            ._priceTiersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductUnitsTableReferences(db, table, p0)
                                .priceTiersRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productUnitId == item.id),
                        typedResults: items),
                  if (altPricesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ProductUnitsTableReferences
                            ._altPricesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductUnitsTableReferences(db, table, p0)
                                .altPricesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productUnitId == item.id),
                        typedResults: items),
                  if (customerGroupPricesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ProductUnitsTableReferences
                            ._customerGroupPricesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductUnitsTableReferences(db, table, p0)
                                .customerGroupPricesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productUnitId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProductUnitsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductUnitsTable,
    ProductUnit,
    $$ProductUnitsTableFilterComposer,
    $$ProductUnitsTableOrderingComposer,
    $$ProductUnitsTableAnnotationComposer,
    $$ProductUnitsTableCreateCompanionBuilder,
    $$ProductUnitsTableUpdateCompanionBuilder,
    (ProductUnit, $$ProductUnitsTableReferences),
    ProductUnit,
    PrefetchHooks Function(
        {bool productId,
        bool productBarcodesRefs,
        bool priceTiersRefs,
        bool altPricesRefs,
        bool customerGroupPricesRefs})>;
typedef $$ProductBarcodesTableCreateCompanionBuilder = ProductBarcodesCompanion
    Function({
  required String id,
  required String productUnitId,
  required String barcode,
  Value<bool> isPrimary,
  Value<bool> isGenerated,
  Value<int> rowid,
});
typedef $$ProductBarcodesTableUpdateCompanionBuilder = ProductBarcodesCompanion
    Function({
  Value<String> id,
  Value<String> productUnitId,
  Value<String> barcode,
  Value<bool> isPrimary,
  Value<bool> isGenerated,
  Value<int> rowid,
});

final class $$ProductBarcodesTableReferences extends BaseReferences<
    _$AppDatabase, $ProductBarcodesTable, ProductBarcode> {
  $$ProductBarcodesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductUnitsTable _productUnitIdTable(_$AppDatabase db) =>
      db.productUnits.createAlias($_aliasNameGenerator(
          db.productBarcodes.productUnitId, db.productUnits.id));

  $$ProductUnitsTableProcessedTableManager get productUnitId {
    final manager = $$ProductUnitsTableTableManager($_db, $_db.productUnits)
        .filter((f) => f.id($_item.productUnitId));
    final item = $_typedResult.readTableOrNull(_productUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ProductBarcodesTableFilterComposer
    extends Composer<_$AppDatabase, $ProductBarcodesTable> {
  $$ProductBarcodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get barcode => $composableBuilder(
      column: $table.barcode, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPrimary => $composableBuilder(
      column: $table.isPrimary, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isGenerated => $composableBuilder(
      column: $table.isGenerated, builder: (column) => ColumnFilters(column));

  $$ProductUnitsTableFilterComposer get productUnitId {
    final $$ProductUnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableFilterComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductBarcodesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductBarcodesTable> {
  $$ProductBarcodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get barcode => $composableBuilder(
      column: $table.barcode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
      column: $table.isPrimary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isGenerated => $composableBuilder(
      column: $table.isGenerated, builder: (column) => ColumnOrderings(column));

  $$ProductUnitsTableOrderingComposer get productUnitId {
    final $$ProductUnitsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableOrderingComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductBarcodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductBarcodesTable> {
  $$ProductBarcodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<bool> get isGenerated => $composableBuilder(
      column: $table.isGenerated, builder: (column) => column);

  $$ProductUnitsTableAnnotationComposer get productUnitId {
    final $$ProductUnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductBarcodesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductBarcodesTable,
    ProductBarcode,
    $$ProductBarcodesTableFilterComposer,
    $$ProductBarcodesTableOrderingComposer,
    $$ProductBarcodesTableAnnotationComposer,
    $$ProductBarcodesTableCreateCompanionBuilder,
    $$ProductBarcodesTableUpdateCompanionBuilder,
    (ProductBarcode, $$ProductBarcodesTableReferences),
    ProductBarcode,
    PrefetchHooks Function({bool productUnitId})> {
  $$ProductBarcodesTableTableManager(
      _$AppDatabase db, $ProductBarcodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductBarcodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductBarcodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductBarcodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<String> barcode = const Value.absent(),
            Value<bool> isPrimary = const Value.absent(),
            Value<bool> isGenerated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductBarcodesCompanion(
            id: id,
            productUnitId: productUnitId,
            barcode: barcode,
            isPrimary: isPrimary,
            isGenerated: isGenerated,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productUnitId,
            required String barcode,
            Value<bool> isPrimary = const Value.absent(),
            Value<bool> isGenerated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductBarcodesCompanion.insert(
            id: id,
            productUnitId: productUnitId,
            barcode: barcode,
            isPrimary: isPrimary,
            isGenerated: isGenerated,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductBarcodesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productUnitId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productUnitId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productUnitId,
                    referencedTable: $$ProductBarcodesTableReferences
                        ._productUnitIdTable(db),
                    referencedColumn: $$ProductBarcodesTableReferences
                        ._productUnitIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ProductBarcodesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductBarcodesTable,
    ProductBarcode,
    $$ProductBarcodesTableFilterComposer,
    $$ProductBarcodesTableOrderingComposer,
    $$ProductBarcodesTableAnnotationComposer,
    $$ProductBarcodesTableCreateCompanionBuilder,
    $$ProductBarcodesTableUpdateCompanionBuilder,
    (ProductBarcode, $$ProductBarcodesTableReferences),
    ProductBarcode,
    PrefetchHooks Function({bool productUnitId})>;
typedef $$PriceTiersTableCreateCompanionBuilder = PriceTiersCompanion Function({
  required String id,
  required String productUnitId,
  Value<int> minQty,
  required int price,
  Value<int> costPrice,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$PriceTiersTableUpdateCompanionBuilder = PriceTiersCompanion Function({
  Value<String> id,
  Value<String> productUnitId,
  Value<int> minQty,
  Value<int> price,
  Value<int> costPrice,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$PriceTiersTableReferences
    extends BaseReferences<_$AppDatabase, $PriceTiersTable, PriceTier> {
  $$PriceTiersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProductUnitsTable _productUnitIdTable(_$AppDatabase db) =>
      db.productUnits.createAlias($_aliasNameGenerator(
          db.priceTiers.productUnitId, db.productUnits.id));

  $$ProductUnitsTableProcessedTableManager get productUnitId {
    final manager = $$ProductUnitsTableTableManager($_db, $_db.productUnits)
        .filter((f) => f.id($_item.productUnitId));
    final item = $_typedResult.readTableOrNull(_productUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$PriceTiersTableFilterComposer
    extends Composer<_$AppDatabase, $PriceTiersTable> {
  $$PriceTiersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minQty => $composableBuilder(
      column: $table.minQty, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get costPrice => $composableBuilder(
      column: $table.costPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$ProductUnitsTableFilterComposer get productUnitId {
    final $$ProductUnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableFilterComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PriceTiersTableOrderingComposer
    extends Composer<_$AppDatabase, $PriceTiersTable> {
  $$PriceTiersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minQty => $composableBuilder(
      column: $table.minQty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get costPrice => $composableBuilder(
      column: $table.costPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$ProductUnitsTableOrderingComposer get productUnitId {
    final $$ProductUnitsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableOrderingComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PriceTiersTableAnnotationComposer
    extends Composer<_$AppDatabase, $PriceTiersTable> {
  $$PriceTiersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get minQty =>
      $composableBuilder(column: $table.minQty, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<int> get costPrice =>
      $composableBuilder(column: $table.costPrice, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ProductUnitsTableAnnotationComposer get productUnitId {
    final $$ProductUnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PriceTiersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PriceTiersTable,
    PriceTier,
    $$PriceTiersTableFilterComposer,
    $$PriceTiersTableOrderingComposer,
    $$PriceTiersTableAnnotationComposer,
    $$PriceTiersTableCreateCompanionBuilder,
    $$PriceTiersTableUpdateCompanionBuilder,
    (PriceTier, $$PriceTiersTableReferences),
    PriceTier,
    PrefetchHooks Function({bool productUnitId})> {
  $$PriceTiersTableTableManager(_$AppDatabase db, $PriceTiersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PriceTiersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PriceTiersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PriceTiersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<int> minQty = const Value.absent(),
            Value<int> price = const Value.absent(),
            Value<int> costPrice = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PriceTiersCompanion(
            id: id,
            productUnitId: productUnitId,
            minQty: minQty,
            price: price,
            costPrice: costPrice,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productUnitId,
            Value<int> minQty = const Value.absent(),
            required int price,
            Value<int> costPrice = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PriceTiersCompanion.insert(
            id: id,
            productUnitId: productUnitId,
            minQty: minQty,
            price: price,
            costPrice: costPrice,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PriceTiersTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productUnitId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productUnitId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productUnitId,
                    referencedTable:
                        $$PriceTiersTableReferences._productUnitIdTable(db),
                    referencedColumn:
                        $$PriceTiersTableReferences._productUnitIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$PriceTiersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PriceTiersTable,
    PriceTier,
    $$PriceTiersTableFilterComposer,
    $$PriceTiersTableOrderingComposer,
    $$PriceTiersTableAnnotationComposer,
    $$PriceTiersTableCreateCompanionBuilder,
    $$PriceTiersTableUpdateCompanionBuilder,
    (PriceTier, $$PriceTiersTableReferences),
    PriceTier,
    PrefetchHooks Function({bool productUnitId})>;
typedef $$AltPricesTableCreateCompanionBuilder = AltPricesCompanion Function({
  required String id,
  required String productUnitId,
  required String label,
  required int price,
  Value<DateTime> createdAt,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$AltPricesTableUpdateCompanionBuilder = AltPricesCompanion Function({
  Value<String> id,
  Value<String> productUnitId,
  Value<String> label,
  Value<int> price,
  Value<DateTime> createdAt,
  Value<int> sortOrder,
  Value<int> rowid,
});

final class $$AltPricesTableReferences
    extends BaseReferences<_$AppDatabase, $AltPricesTable, AltPrice> {
  $$AltPricesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProductUnitsTable _productUnitIdTable(_$AppDatabase db) =>
      db.productUnits.createAlias(
          $_aliasNameGenerator(db.altPrices.productUnitId, db.productUnits.id));

  $$ProductUnitsTableProcessedTableManager get productUnitId {
    final manager = $$ProductUnitsTableTableManager($_db, $_db.productUnits)
        .filter((f) => f.id($_item.productUnitId));
    final item = $_typedResult.readTableOrNull(_productUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AltPricesTableFilterComposer
    extends Composer<_$AppDatabase, $AltPricesTable> {
  $$AltPricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  $$ProductUnitsTableFilterComposer get productUnitId {
    final $$ProductUnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableFilterComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AltPricesTableOrderingComposer
    extends Composer<_$AppDatabase, $AltPricesTable> {
  $$AltPricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  $$ProductUnitsTableOrderingComposer get productUnitId {
    final $$ProductUnitsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableOrderingComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AltPricesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AltPricesTable> {
  $$AltPricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$ProductUnitsTableAnnotationComposer get productUnitId {
    final $$ProductUnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AltPricesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AltPricesTable,
    AltPrice,
    $$AltPricesTableFilterComposer,
    $$AltPricesTableOrderingComposer,
    $$AltPricesTableAnnotationComposer,
    $$AltPricesTableCreateCompanionBuilder,
    $$AltPricesTableUpdateCompanionBuilder,
    (AltPrice, $$AltPricesTableReferences),
    AltPrice,
    PrefetchHooks Function({bool productUnitId})> {
  $$AltPricesTableTableManager(_$AppDatabase db, $AltPricesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AltPricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AltPricesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AltPricesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<int> price = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AltPricesCompanion(
            id: id,
            productUnitId: productUnitId,
            label: label,
            price: price,
            createdAt: createdAt,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productUnitId,
            required String label,
            required int price,
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AltPricesCompanion.insert(
            id: id,
            productUnitId: productUnitId,
            label: label,
            price: price,
            createdAt: createdAt,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AltPricesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productUnitId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productUnitId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productUnitId,
                    referencedTable:
                        $$AltPricesTableReferences._productUnitIdTable(db),
                    referencedColumn:
                        $$AltPricesTableReferences._productUnitIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$AltPricesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AltPricesTable,
    AltPrice,
    $$AltPricesTableFilterComposer,
    $$AltPricesTableOrderingComposer,
    $$AltPricesTableAnnotationComposer,
    $$AltPricesTableCreateCompanionBuilder,
    $$AltPricesTableUpdateCompanionBuilder,
    (AltPrice, $$AltPricesTableReferences),
    AltPrice,
    PrefetchHooks Function({bool productUnitId})>;
typedef $$CustomerGroupsTableCreateCompanionBuilder = CustomerGroupsCompanion
    Function({
  required String id,
  required String name,
  Value<String?> color,
  Value<int> rowid,
});
typedef $$CustomerGroupsTableUpdateCompanionBuilder = CustomerGroupsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String?> color,
  Value<int> rowid,
});

final class $$CustomerGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $CustomerGroupsTable, CustomerGroup> {
  $$CustomerGroupsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CustomerGroupPricesTable,
      List<CustomerGroupPrice>> _customerGroupPricesRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.customerGroupPrices,
          aliasName: $_aliasNameGenerator(
              db.customerGroups.id, db.customerGroupPrices.customerGroupId));

  $$CustomerGroupPricesTableProcessedTableManager get customerGroupPricesRefs {
    final manager =
        $$CustomerGroupPricesTableTableManager($_db, $_db.customerGroupPrices)
            .filter((f) => f.customerGroupId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_customerGroupPricesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$CustomerGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $CustomerGroupsTable> {
  $$CustomerGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  Expression<bool> customerGroupPricesRefs(
      Expression<bool> Function($$CustomerGroupPricesTableFilterComposer f) f) {
    final $$CustomerGroupPricesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.customerGroupPrices,
        getReferencedColumn: (t) => t.customerGroupId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CustomerGroupPricesTableFilterComposer(
              $db: $db,
              $table: $db.customerGroupPrices,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CustomerGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomerGroupsTable> {
  $$CustomerGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));
}

class $$CustomerGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomerGroupsTable> {
  $$CustomerGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  Expression<T> customerGroupPricesRefs<T extends Object>(
      Expression<T> Function($$CustomerGroupPricesTableAnnotationComposer a)
          f) {
    final $$CustomerGroupPricesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.customerGroupPrices,
            getReferencedColumn: (t) => t.customerGroupId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$CustomerGroupPricesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.customerGroupPrices,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$CustomerGroupsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CustomerGroupsTable,
    CustomerGroup,
    $$CustomerGroupsTableFilterComposer,
    $$CustomerGroupsTableOrderingComposer,
    $$CustomerGroupsTableAnnotationComposer,
    $$CustomerGroupsTableCreateCompanionBuilder,
    $$CustomerGroupsTableUpdateCompanionBuilder,
    (CustomerGroup, $$CustomerGroupsTableReferences),
    CustomerGroup,
    PrefetchHooks Function({bool customerGroupPricesRefs})> {
  $$CustomerGroupsTableTableManager(
      _$AppDatabase db, $CustomerGroupsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomerGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomerGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomerGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> color = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomerGroupsCompanion(
            id: id,
            name: name,
            color: color,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> color = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomerGroupsCompanion.insert(
            id: id,
            name: name,
            color: color,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$CustomerGroupsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({customerGroupPricesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (customerGroupPricesRefs) db.customerGroupPrices
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (customerGroupPricesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$CustomerGroupsTableReferences
                            ._customerGroupPricesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$CustomerGroupsTableReferences(db, table, p0)
                                .customerGroupPricesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.customerGroupId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$CustomerGroupsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CustomerGroupsTable,
    CustomerGroup,
    $$CustomerGroupsTableFilterComposer,
    $$CustomerGroupsTableOrderingComposer,
    $$CustomerGroupsTableAnnotationComposer,
    $$CustomerGroupsTableCreateCompanionBuilder,
    $$CustomerGroupsTableUpdateCompanionBuilder,
    (CustomerGroup, $$CustomerGroupsTableReferences),
    CustomerGroup,
    PrefetchHooks Function({bool customerGroupPricesRefs})>;
typedef $$CustomerGroupPricesTableCreateCompanionBuilder
    = CustomerGroupPricesCompanion Function({
  required String id,
  required String productUnitId,
  required String customerGroupId,
  required int price,
  Value<int> rowid,
});
typedef $$CustomerGroupPricesTableUpdateCompanionBuilder
    = CustomerGroupPricesCompanion Function({
  Value<String> id,
  Value<String> productUnitId,
  Value<String> customerGroupId,
  Value<int> price,
  Value<int> rowid,
});

final class $$CustomerGroupPricesTableReferences extends BaseReferences<
    _$AppDatabase, $CustomerGroupPricesTable, CustomerGroupPrice> {
  $$CustomerGroupPricesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductUnitsTable _productUnitIdTable(_$AppDatabase db) =>
      db.productUnits.createAlias($_aliasNameGenerator(
          db.customerGroupPrices.productUnitId, db.productUnits.id));

  $$ProductUnitsTableProcessedTableManager get productUnitId {
    final manager = $$ProductUnitsTableTableManager($_db, $_db.productUnits)
        .filter((f) => f.id($_item.productUnitId));
    final item = $_typedResult.readTableOrNull(_productUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $CustomerGroupsTable _customerGroupIdTable(_$AppDatabase db) =>
      db.customerGroups.createAlias($_aliasNameGenerator(
          db.customerGroupPrices.customerGroupId, db.customerGroups.id));

  $$CustomerGroupsTableProcessedTableManager get customerGroupId {
    final manager = $$CustomerGroupsTableTableManager($_db, $_db.customerGroups)
        .filter((f) => f.id($_item.customerGroupId));
    final item = $_typedResult.readTableOrNull(_customerGroupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$CustomerGroupPricesTableFilterComposer
    extends Composer<_$AppDatabase, $CustomerGroupPricesTable> {
  $$CustomerGroupPricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  $$ProductUnitsTableFilterComposer get productUnitId {
    final $$ProductUnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableFilterComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$CustomerGroupsTableFilterComposer get customerGroupId {
    final $$CustomerGroupsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.customerGroupId,
        referencedTable: $db.customerGroups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CustomerGroupsTableFilterComposer(
              $db: $db,
              $table: $db.customerGroups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$CustomerGroupPricesTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomerGroupPricesTable> {
  $$CustomerGroupPricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  $$ProductUnitsTableOrderingComposer get productUnitId {
    final $$ProductUnitsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableOrderingComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$CustomerGroupsTableOrderingComposer get customerGroupId {
    final $$CustomerGroupsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.customerGroupId,
        referencedTable: $db.customerGroups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CustomerGroupsTableOrderingComposer(
              $db: $db,
              $table: $db.customerGroups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$CustomerGroupPricesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomerGroupPricesTable> {
  $$CustomerGroupPricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  $$ProductUnitsTableAnnotationComposer get productUnitId {
    final $$ProductUnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productUnitId,
        referencedTable: $db.productUnits,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductUnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.productUnits,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$CustomerGroupsTableAnnotationComposer get customerGroupId {
    final $$CustomerGroupsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.customerGroupId,
        referencedTable: $db.customerGroups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CustomerGroupsTableAnnotationComposer(
              $db: $db,
              $table: $db.customerGroups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$CustomerGroupPricesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CustomerGroupPricesTable,
    CustomerGroupPrice,
    $$CustomerGroupPricesTableFilterComposer,
    $$CustomerGroupPricesTableOrderingComposer,
    $$CustomerGroupPricesTableAnnotationComposer,
    $$CustomerGroupPricesTableCreateCompanionBuilder,
    $$CustomerGroupPricesTableUpdateCompanionBuilder,
    (CustomerGroupPrice, $$CustomerGroupPricesTableReferences),
    CustomerGroupPrice,
    PrefetchHooks Function({bool productUnitId, bool customerGroupId})> {
  $$CustomerGroupPricesTableTableManager(
      _$AppDatabase db, $CustomerGroupPricesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomerGroupPricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomerGroupPricesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomerGroupPricesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<String> customerGroupId = const Value.absent(),
            Value<int> price = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomerGroupPricesCompanion(
            id: id,
            productUnitId: productUnitId,
            customerGroupId: customerGroupId,
            price: price,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productUnitId,
            required String customerGroupId,
            required int price,
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomerGroupPricesCompanion.insert(
            id: id,
            productUnitId: productUnitId,
            customerGroupId: customerGroupId,
            price: price,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$CustomerGroupPricesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {productUnitId = false, customerGroupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productUnitId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productUnitId,
                    referencedTable: $$CustomerGroupPricesTableReferences
                        ._productUnitIdTable(db),
                    referencedColumn: $$CustomerGroupPricesTableReferences
                        ._productUnitIdTable(db)
                        .id,
                  ) as T;
                }
                if (customerGroupId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.customerGroupId,
                    referencedTable: $$CustomerGroupPricesTableReferences
                        ._customerGroupIdTable(db),
                    referencedColumn: $$CustomerGroupPricesTableReferences
                        ._customerGroupIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$CustomerGroupPricesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CustomerGroupPricesTable,
    CustomerGroupPrice,
    $$CustomerGroupPricesTableFilterComposer,
    $$CustomerGroupPricesTableOrderingComposer,
    $$CustomerGroupPricesTableAnnotationComposer,
    $$CustomerGroupPricesTableCreateCompanionBuilder,
    $$CustomerGroupPricesTableUpdateCompanionBuilder,
    (CustomerGroupPrice, $$CustomerGroupPricesTableReferences),
    CustomerGroupPrice,
    PrefetchHooks Function({bool productUnitId, bool customerGroupId})>;
typedef $$CustomersTableCreateCompanionBuilder = CustomersCompanion Function({
  required String id,
  required String name,
  Value<String?> phone,
  Value<String?> address,
  Value<String?> customerGroupId,
  Value<int> creditLimit,
  Value<int> outstandingDebt,
  Value<int> loyaltyPoints,
  Value<String?> notes,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$CustomersTableUpdateCompanionBuilder = CustomersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> phone,
  Value<String?> address,
  Value<String?> customerGroupId,
  Value<int> creditLimit,
  Value<int> outstandingDebt,
  Value<int> loyaltyPoints,
  Value<String?> notes,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerGroupId => $composableBuilder(
      column: $table.customerGroupId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get outstandingDebt => $composableBuilder(
      column: $table.outstandingDebt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get loyaltyPoints => $composableBuilder(
      column: $table.loyaltyPoints, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerGroupId => $composableBuilder(
      column: $table.customerGroupId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get outstandingDebt => $composableBuilder(
      column: $table.outstandingDebt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get loyaltyPoints => $composableBuilder(
      column: $table.loyaltyPoints,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get customerGroupId => $composableBuilder(
      column: $table.customerGroupId, builder: (column) => column);

  GeneratedColumn<int> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => column);

  GeneratedColumn<int> get outstandingDebt => $composableBuilder(
      column: $table.outstandingDebt, builder: (column) => column);

  GeneratedColumn<int> get loyaltyPoints => $composableBuilder(
      column: $table.loyaltyPoints, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CustomersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CustomersTable,
    Customer,
    $$CustomersTableFilterComposer,
    $$CustomersTableOrderingComposer,
    $$CustomersTableAnnotationComposer,
    $$CustomersTableCreateCompanionBuilder,
    $$CustomersTableUpdateCompanionBuilder,
    (Customer, BaseReferences<_$AppDatabase, $CustomersTable, Customer>),
    Customer,
    PrefetchHooks Function()> {
  $$CustomersTableTableManager(_$AppDatabase db, $CustomersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<String?> customerGroupId = const Value.absent(),
            Value<int> creditLimit = const Value.absent(),
            Value<int> outstandingDebt = const Value.absent(),
            Value<int> loyaltyPoints = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomersCompanion(
            id: id,
            name: name,
            phone: phone,
            address: address,
            customerGroupId: customerGroupId,
            creditLimit: creditLimit,
            outstandingDebt: outstandingDebt,
            loyaltyPoints: loyaltyPoints,
            notes: notes,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> phone = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<String?> customerGroupId = const Value.absent(),
            Value<int> creditLimit = const Value.absent(),
            Value<int> outstandingDebt = const Value.absent(),
            Value<int> loyaltyPoints = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomersCompanion.insert(
            id: id,
            name: name,
            phone: phone,
            address: address,
            customerGroupId: customerGroupId,
            creditLimit: creditLimit,
            outstandingDebt: outstandingDebt,
            loyaltyPoints: loyaltyPoints,
            notes: notes,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CustomersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CustomersTable,
    Customer,
    $$CustomersTableFilterComposer,
    $$CustomersTableOrderingComposer,
    $$CustomersTableAnnotationComposer,
    $$CustomersTableCreateCompanionBuilder,
    $$CustomersTableUpdateCompanionBuilder,
    (Customer, BaseReferences<_$AppDatabase, $CustomersTable, Customer>),
    Customer,
    PrefetchHooks Function()>;
typedef $$TransactionsTableCreateCompanionBuilder = TransactionsCompanion
    Function({
  required String id,
  required String localId,
  Value<String?> kasirId,
  Value<String?> customerId,
  Value<String?> customerName,
  required String status,
  required int total,
  required int paid,
  required int changeAmount,
  required String paymentMethod,
  Value<String?> internalNote,
  Value<String?> strukNote,
  Value<String?> employeeName,
  Value<int> pointsEarned,
  Value<bool> changeTaken,
  Value<String?> checkedItemIds,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});
typedef $$TransactionsTableUpdateCompanionBuilder = TransactionsCompanion
    Function({
  Value<String> id,
  Value<String> localId,
  Value<String?> kasirId,
  Value<String?> customerId,
  Value<String?> customerName,
  Value<String> status,
  Value<int> total,
  Value<int> paid,
  Value<int> changeAmount,
  Value<String> paymentMethod,
  Value<String?> internalNote,
  Value<String?> strukNote,
  Value<String?> employeeName,
  Value<int> pointsEarned,
  Value<bool> changeTaken,
  Value<String?> checkedItemIds,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});

final class $$TransactionsTableReferences
    extends BaseReferences<_$AppDatabase, $TransactionsTable, Transaction> {
  $$TransactionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TransactionItemsTable, List<TransactionItem>>
      _transactionItemsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.transactionItems,
              aliasName: $_aliasNameGenerator(
                  db.transactions.id, db.transactionItems.transactionId));

  $$TransactionItemsTableProcessedTableManager get transactionItemsRefs {
    final manager =
        $$TransactionItemsTableTableManager($_db, $_db.transactionItems)
            .filter((f) => f.transactionId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_transactionItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$TransactionPaymentsTable,
      List<TransactionPayment>> _transactionPaymentsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.transactionPayments,
          aliasName: $_aliasNameGenerator(
              db.transactions.id, db.transactionPayments.transactionId));

  $$TransactionPaymentsTableProcessedTableManager get transactionPaymentsRefs {
    final manager =
        $$TransactionPaymentsTableTableManager($_db, $_db.transactionPayments)
            .filter((f) => f.transactionId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_transactionPaymentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerName => $composableBuilder(
      column: $table.customerName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get paid => $composableBuilder(
      column: $table.paid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get changeAmount => $composableBuilder(
      column: $table.changeAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get internalNote => $composableBuilder(
      column: $table.internalNote, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get strukNote => $composableBuilder(
      column: $table.strukNote, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get employeeName => $composableBuilder(
      column: $table.employeeName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pointsEarned => $composableBuilder(
      column: $table.pointsEarned, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get changeTaken => $composableBuilder(
      column: $table.changeTaken, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get checkedItemIds => $composableBuilder(
      column: $table.checkedItemIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> transactionItemsRefs(
      Expression<bool> Function($$TransactionItemsTableFilterComposer f) f) {
    final $$TransactionItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.transactionItems,
        getReferencedColumn: (t) => t.transactionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionItemsTableFilterComposer(
              $db: $db,
              $table: $db.transactionItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> transactionPaymentsRefs(
      Expression<bool> Function($$TransactionPaymentsTableFilterComposer f) f) {
    final $$TransactionPaymentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.transactionPayments,
        getReferencedColumn: (t) => t.transactionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionPaymentsTableFilterComposer(
              $db: $db,
              $table: $db.transactionPayments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerName => $composableBuilder(
      column: $table.customerName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get paid => $composableBuilder(
      column: $table.paid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get changeAmount => $composableBuilder(
      column: $table.changeAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get internalNote => $composableBuilder(
      column: $table.internalNote,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get strukNote => $composableBuilder(
      column: $table.strukNote, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get employeeName => $composableBuilder(
      column: $table.employeeName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pointsEarned => $composableBuilder(
      column: $table.pointsEarned,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get changeTaken => $composableBuilder(
      column: $table.changeTaken, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get checkedItemIds => $composableBuilder(
      column: $table.checkedItemIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get kasirId =>
      $composableBuilder(column: $table.kasirId, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => column);

  GeneratedColumn<String> get customerName => $composableBuilder(
      column: $table.customerName, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<int> get paid =>
      $composableBuilder(column: $table.paid, builder: (column) => column);

  GeneratedColumn<int> get changeAmount => $composableBuilder(
      column: $table.changeAmount, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => column);

  GeneratedColumn<String> get internalNote => $composableBuilder(
      column: $table.internalNote, builder: (column) => column);

  GeneratedColumn<String> get strukNote =>
      $composableBuilder(column: $table.strukNote, builder: (column) => column);

  GeneratedColumn<String> get employeeName => $composableBuilder(
      column: $table.employeeName, builder: (column) => column);

  GeneratedColumn<int> get pointsEarned => $composableBuilder(
      column: $table.pointsEarned, builder: (column) => column);

  GeneratedColumn<bool> get changeTaken => $composableBuilder(
      column: $table.changeTaken, builder: (column) => column);

  GeneratedColumn<String> get checkedItemIds => $composableBuilder(
      column: $table.checkedItemIds, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  Expression<T> transactionItemsRefs<T extends Object>(
      Expression<T> Function($$TransactionItemsTableAnnotationComposer a) f) {
    final $$TransactionItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.transactionItems,
        getReferencedColumn: (t) => t.transactionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.transactionItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> transactionPaymentsRefs<T extends Object>(
      Expression<T> Function($$TransactionPaymentsTableAnnotationComposer a)
          f) {
    final $$TransactionPaymentsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.transactionPayments,
            getReferencedColumn: (t) => t.transactionId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$TransactionPaymentsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.transactionPayments,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$TransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableAnnotationComposer,
    $$TransactionsTableCreateCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder,
    (Transaction, $$TransactionsTableReferences),
    Transaction,
    PrefetchHooks Function(
        {bool transactionItemsRefs, bool transactionPaymentsRefs})> {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> localId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            Value<String?> customerName = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> total = const Value.absent(),
            Value<int> paid = const Value.absent(),
            Value<int> changeAmount = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<String?> internalNote = const Value.absent(),
            Value<String?> strukNote = const Value.absent(),
            Value<String?> employeeName = const Value.absent(),
            Value<int> pointsEarned = const Value.absent(),
            Value<bool> changeTaken = const Value.absent(),
            Value<String?> checkedItemIds = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionsCompanion(
            id: id,
            localId: localId,
            kasirId: kasirId,
            customerId: customerId,
            customerName: customerName,
            status: status,
            total: total,
            paid: paid,
            changeAmount: changeAmount,
            paymentMethod: paymentMethod,
            internalNote: internalNote,
            strukNote: strukNote,
            employeeName: employeeName,
            pointsEarned: pointsEarned,
            changeTaken: changeTaken,
            checkedItemIds: checkedItemIds,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String localId,
            Value<String?> kasirId = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            Value<String?> customerName = const Value.absent(),
            required String status,
            required int total,
            required int paid,
            required int changeAmount,
            required String paymentMethod,
            Value<String?> internalNote = const Value.absent(),
            Value<String?> strukNote = const Value.absent(),
            Value<String?> employeeName = const Value.absent(),
            Value<int> pointsEarned = const Value.absent(),
            Value<bool> changeTaken = const Value.absent(),
            Value<String?> checkedItemIds = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionsCompanion.insert(
            id: id,
            localId: localId,
            kasirId: kasirId,
            customerId: customerId,
            customerName: customerName,
            status: status,
            total: total,
            paid: paid,
            changeAmount: changeAmount,
            paymentMethod: paymentMethod,
            internalNote: internalNote,
            strukNote: strukNote,
            employeeName: employeeName,
            pointsEarned: pointsEarned,
            changeTaken: changeTaken,
            checkedItemIds: checkedItemIds,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TransactionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {transactionItemsRefs = false, transactionPaymentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (transactionItemsRefs) db.transactionItems,
                if (transactionPaymentsRefs) db.transactionPayments
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (transactionItemsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$TransactionsTableReferences
                            ._transactionItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TransactionsTableReferences(db, table, p0)
                                .transactionItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.transactionId == item.id),
                        typedResults: items),
                  if (transactionPaymentsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$TransactionsTableReferences
                            ._transactionPaymentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TransactionsTableReferences(db, table, p0)
                                .transactionPaymentsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.transactionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$TransactionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableAnnotationComposer,
    $$TransactionsTableCreateCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder,
    (Transaction, $$TransactionsTableReferences),
    Transaction,
    PrefetchHooks Function(
        {bool transactionItemsRefs, bool transactionPaymentsRefs})>;
typedef $$TransactionItemsTableCreateCompanionBuilder
    = TransactionItemsCompanion Function({
  required String id,
  required String transactionId,
  required String productId,
  required String productUnitId,
  required double qty,
  required int priceAtSale,
  required int originalPrice,
  Value<bool> priceOverridden,
  Value<int> costAtSale,
  Value<String?> itemNote,
  required int subtotal,
  Value<DateTime?> addedAt,
  Value<DateTime?> returnedAt,
  Value<int> rowid,
});
typedef $$TransactionItemsTableUpdateCompanionBuilder
    = TransactionItemsCompanion Function({
  Value<String> id,
  Value<String> transactionId,
  Value<String> productId,
  Value<String> productUnitId,
  Value<double> qty,
  Value<int> priceAtSale,
  Value<int> originalPrice,
  Value<bool> priceOverridden,
  Value<int> costAtSale,
  Value<String?> itemNote,
  Value<int> subtotal,
  Value<DateTime?> addedAt,
  Value<DateTime?> returnedAt,
  Value<int> rowid,
});

final class $$TransactionItemsTableReferences extends BaseReferences<
    _$AppDatabase, $TransactionItemsTable, TransactionItem> {
  $$TransactionItemsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TransactionsTable _transactionIdTable(_$AppDatabase db) =>
      db.transactions.createAlias($_aliasNameGenerator(
          db.transactionItems.transactionId, db.transactions.id));

  $$TransactionsTableProcessedTableManager get transactionId {
    final manager = $$TransactionsTableTableManager($_db, $_db.transactions)
        .filter((f) => f.id($_item.transactionId));
    final item = $_typedResult.readTableOrNull(_transactionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TransactionItemsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionItemsTable> {
  $$TransactionItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get qty => $composableBuilder(
      column: $table.qty, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priceAtSale => $composableBuilder(
      column: $table.priceAtSale, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get originalPrice => $composableBuilder(
      column: $table.originalPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get priceOverridden => $composableBuilder(
      column: $table.priceOverridden,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get costAtSale => $composableBuilder(
      column: $table.costAtSale, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get itemNote => $composableBuilder(
      column: $table.itemNote, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get subtotal => $composableBuilder(
      column: $table.subtotal, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get returnedAt => $composableBuilder(
      column: $table.returnedAt, builder: (column) => ColumnFilters(column));

  $$TransactionsTableFilterComposer get transactionId {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.transactionId,
        referencedTable: $db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionsTableFilterComposer(
              $db: $db,
              $table: $db.transactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TransactionItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionItemsTable> {
  $$TransactionItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get qty => $composableBuilder(
      column: $table.qty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priceAtSale => $composableBuilder(
      column: $table.priceAtSale, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get originalPrice => $composableBuilder(
      column: $table.originalPrice,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get priceOverridden => $composableBuilder(
      column: $table.priceOverridden,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get costAtSale => $composableBuilder(
      column: $table.costAtSale, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get itemNote => $composableBuilder(
      column: $table.itemNote, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get subtotal => $composableBuilder(
      column: $table.subtotal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get returnedAt => $composableBuilder(
      column: $table.returnedAt, builder: (column) => ColumnOrderings(column));

  $$TransactionsTableOrderingComposer get transactionId {
    final $$TransactionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.transactionId,
        referencedTable: $db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionsTableOrderingComposer(
              $db: $db,
              $table: $db.transactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TransactionItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionItemsTable> {
  $$TransactionItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId, builder: (column) => column);

  GeneratedColumn<double> get qty =>
      $composableBuilder(column: $table.qty, builder: (column) => column);

  GeneratedColumn<int> get priceAtSale => $composableBuilder(
      column: $table.priceAtSale, builder: (column) => column);

  GeneratedColumn<int> get originalPrice => $composableBuilder(
      column: $table.originalPrice, builder: (column) => column);

  GeneratedColumn<bool> get priceOverridden => $composableBuilder(
      column: $table.priceOverridden, builder: (column) => column);

  GeneratedColumn<int> get costAtSale => $composableBuilder(
      column: $table.costAtSale, builder: (column) => column);

  GeneratedColumn<String> get itemNote =>
      $composableBuilder(column: $table.itemNote, builder: (column) => column);

  GeneratedColumn<int> get subtotal =>
      $composableBuilder(column: $table.subtotal, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get returnedAt => $composableBuilder(
      column: $table.returnedAt, builder: (column) => column);

  $$TransactionsTableAnnotationComposer get transactionId {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.transactionId,
        referencedTable: $db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionsTableAnnotationComposer(
              $db: $db,
              $table: $db.transactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TransactionItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TransactionItemsTable,
    TransactionItem,
    $$TransactionItemsTableFilterComposer,
    $$TransactionItemsTableOrderingComposer,
    $$TransactionItemsTableAnnotationComposer,
    $$TransactionItemsTableCreateCompanionBuilder,
    $$TransactionItemsTableUpdateCompanionBuilder,
    (TransactionItem, $$TransactionItemsTableReferences),
    TransactionItem,
    PrefetchHooks Function({bool transactionId})> {
  $$TransactionItemsTableTableManager(
      _$AppDatabase db, $TransactionItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> transactionId = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<double> qty = const Value.absent(),
            Value<int> priceAtSale = const Value.absent(),
            Value<int> originalPrice = const Value.absent(),
            Value<bool> priceOverridden = const Value.absent(),
            Value<int> costAtSale = const Value.absent(),
            Value<String?> itemNote = const Value.absent(),
            Value<int> subtotal = const Value.absent(),
            Value<DateTime?> addedAt = const Value.absent(),
            Value<DateTime?> returnedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionItemsCompanion(
            id: id,
            transactionId: transactionId,
            productId: productId,
            productUnitId: productUnitId,
            qty: qty,
            priceAtSale: priceAtSale,
            originalPrice: originalPrice,
            priceOverridden: priceOverridden,
            costAtSale: costAtSale,
            itemNote: itemNote,
            subtotal: subtotal,
            addedAt: addedAt,
            returnedAt: returnedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String transactionId,
            required String productId,
            required String productUnitId,
            required double qty,
            required int priceAtSale,
            required int originalPrice,
            Value<bool> priceOverridden = const Value.absent(),
            Value<int> costAtSale = const Value.absent(),
            Value<String?> itemNote = const Value.absent(),
            required int subtotal,
            Value<DateTime?> addedAt = const Value.absent(),
            Value<DateTime?> returnedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionItemsCompanion.insert(
            id: id,
            transactionId: transactionId,
            productId: productId,
            productUnitId: productUnitId,
            qty: qty,
            priceAtSale: priceAtSale,
            originalPrice: originalPrice,
            priceOverridden: priceOverridden,
            costAtSale: costAtSale,
            itemNote: itemNote,
            subtotal: subtotal,
            addedAt: addedAt,
            returnedAt: returnedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TransactionItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({transactionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (transactionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.transactionId,
                    referencedTable: $$TransactionItemsTableReferences
                        ._transactionIdTable(db),
                    referencedColumn: $$TransactionItemsTableReferences
                        ._transactionIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TransactionItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TransactionItemsTable,
    TransactionItem,
    $$TransactionItemsTableFilterComposer,
    $$TransactionItemsTableOrderingComposer,
    $$TransactionItemsTableAnnotationComposer,
    $$TransactionItemsTableCreateCompanionBuilder,
    $$TransactionItemsTableUpdateCompanionBuilder,
    (TransactionItem, $$TransactionItemsTableReferences),
    TransactionItem,
    PrefetchHooks Function({bool transactionId})>;
typedef $$TransactionPaymentsTableCreateCompanionBuilder
    = TransactionPaymentsCompanion Function({
  required String id,
  required String transactionId,
  required int amount,
  required String method,
  Value<DateTime> paidAt,
  Value<String?> kasirId,
  Value<String?> note,
  Value<int> changeGiven,
  Value<bool> changeTaken,
  Value<bool> voided,
  Value<int> rowid,
});
typedef $$TransactionPaymentsTableUpdateCompanionBuilder
    = TransactionPaymentsCompanion Function({
  Value<String> id,
  Value<String> transactionId,
  Value<int> amount,
  Value<String> method,
  Value<DateTime> paidAt,
  Value<String?> kasirId,
  Value<String?> note,
  Value<int> changeGiven,
  Value<bool> changeTaken,
  Value<bool> voided,
  Value<int> rowid,
});

final class $$TransactionPaymentsTableReferences extends BaseReferences<
    _$AppDatabase, $TransactionPaymentsTable, TransactionPayment> {
  $$TransactionPaymentsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TransactionsTable _transactionIdTable(_$AppDatabase db) =>
      db.transactions.createAlias($_aliasNameGenerator(
          db.transactionPayments.transactionId, db.transactions.id));

  $$TransactionsTableProcessedTableManager get transactionId {
    final manager = $$TransactionsTableTableManager($_db, $_db.transactions)
        .filter((f) => f.id($_item.transactionId));
    final item = $_typedResult.readTableOrNull(_transactionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TransactionPaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionPaymentsTable> {
  $$TransactionPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get method => $composableBuilder(
      column: $table.method, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get paidAt => $composableBuilder(
      column: $table.paidAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get changeGiven => $composableBuilder(
      column: $table.changeGiven, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get changeTaken => $composableBuilder(
      column: $table.changeTaken, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get voided => $composableBuilder(
      column: $table.voided, builder: (column) => ColumnFilters(column));

  $$TransactionsTableFilterComposer get transactionId {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.transactionId,
        referencedTable: $db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionsTableFilterComposer(
              $db: $db,
              $table: $db.transactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TransactionPaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionPaymentsTable> {
  $$TransactionPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get method => $composableBuilder(
      column: $table.method, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get paidAt => $composableBuilder(
      column: $table.paidAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get changeGiven => $composableBuilder(
      column: $table.changeGiven, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get changeTaken => $composableBuilder(
      column: $table.changeTaken, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get voided => $composableBuilder(
      column: $table.voided, builder: (column) => ColumnOrderings(column));

  $$TransactionsTableOrderingComposer get transactionId {
    final $$TransactionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.transactionId,
        referencedTable: $db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionsTableOrderingComposer(
              $db: $db,
              $table: $db.transactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TransactionPaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionPaymentsTable> {
  $$TransactionPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<DateTime> get paidAt =>
      $composableBuilder(column: $table.paidAt, builder: (column) => column);

  GeneratedColumn<String> get kasirId =>
      $composableBuilder(column: $table.kasirId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get changeGiven => $composableBuilder(
      column: $table.changeGiven, builder: (column) => column);

  GeneratedColumn<bool> get changeTaken => $composableBuilder(
      column: $table.changeTaken, builder: (column) => column);

  GeneratedColumn<bool> get voided =>
      $composableBuilder(column: $table.voided, builder: (column) => column);

  $$TransactionsTableAnnotationComposer get transactionId {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.transactionId,
        referencedTable: $db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TransactionsTableAnnotationComposer(
              $db: $db,
              $table: $db.transactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TransactionPaymentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TransactionPaymentsTable,
    TransactionPayment,
    $$TransactionPaymentsTableFilterComposer,
    $$TransactionPaymentsTableOrderingComposer,
    $$TransactionPaymentsTableAnnotationComposer,
    $$TransactionPaymentsTableCreateCompanionBuilder,
    $$TransactionPaymentsTableUpdateCompanionBuilder,
    (TransactionPayment, $$TransactionPaymentsTableReferences),
    TransactionPayment,
    PrefetchHooks Function({bool transactionId})> {
  $$TransactionPaymentsTableTableManager(
      _$AppDatabase db, $TransactionPaymentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionPaymentsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionPaymentsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> transactionId = const Value.absent(),
            Value<int> amount = const Value.absent(),
            Value<String> method = const Value.absent(),
            Value<DateTime> paidAt = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<int> changeGiven = const Value.absent(),
            Value<bool> changeTaken = const Value.absent(),
            Value<bool> voided = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionPaymentsCompanion(
            id: id,
            transactionId: transactionId,
            amount: amount,
            method: method,
            paidAt: paidAt,
            kasirId: kasirId,
            note: note,
            changeGiven: changeGiven,
            changeTaken: changeTaken,
            voided: voided,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String transactionId,
            required int amount,
            required String method,
            Value<DateTime> paidAt = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<int> changeGiven = const Value.absent(),
            Value<bool> changeTaken = const Value.absent(),
            Value<bool> voided = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionPaymentsCompanion.insert(
            id: id,
            transactionId: transactionId,
            amount: amount,
            method: method,
            paidAt: paidAt,
            kasirId: kasirId,
            note: note,
            changeGiven: changeGiven,
            changeTaken: changeTaken,
            voided: voided,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TransactionPaymentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({transactionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (transactionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.transactionId,
                    referencedTable: $$TransactionPaymentsTableReferences
                        ._transactionIdTable(db),
                    referencedColumn: $$TransactionPaymentsTableReferences
                        ._transactionIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TransactionPaymentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TransactionPaymentsTable,
    TransactionPayment,
    $$TransactionPaymentsTableFilterComposer,
    $$TransactionPaymentsTableOrderingComposer,
    $$TransactionPaymentsTableAnnotationComposer,
    $$TransactionPaymentsTableCreateCompanionBuilder,
    $$TransactionPaymentsTableUpdateCompanionBuilder,
    (TransactionPayment, $$TransactionPaymentsTableReferences),
    TransactionPayment,
    PrefetchHooks Function({bool transactionId})>;
typedef $$HeldOrdersTableCreateCompanionBuilder = HeldOrdersCompanion Function({
  required String id,
  required String label,
  required String cartJson,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$HeldOrdersTableUpdateCompanionBuilder = HeldOrdersCompanion Function({
  Value<String> id,
  Value<String> label,
  Value<String> cartJson,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$HeldOrdersTableFilterComposer
    extends Composer<_$AppDatabase, $HeldOrdersTable> {
  $$HeldOrdersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cartJson => $composableBuilder(
      column: $table.cartJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$HeldOrdersTableOrderingComposer
    extends Composer<_$AppDatabase, $HeldOrdersTable> {
  $$HeldOrdersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cartJson => $composableBuilder(
      column: $table.cartJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$HeldOrdersTableAnnotationComposer
    extends Composer<_$AppDatabase, $HeldOrdersTable> {
  $$HeldOrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get cartJson =>
      $composableBuilder(column: $table.cartJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$HeldOrdersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $HeldOrdersTable,
    HeldOrder,
    $$HeldOrdersTableFilterComposer,
    $$HeldOrdersTableOrderingComposer,
    $$HeldOrdersTableAnnotationComposer,
    $$HeldOrdersTableCreateCompanionBuilder,
    $$HeldOrdersTableUpdateCompanionBuilder,
    (HeldOrder, BaseReferences<_$AppDatabase, $HeldOrdersTable, HeldOrder>),
    HeldOrder,
    PrefetchHooks Function()> {
  $$HeldOrdersTableTableManager(_$AppDatabase db, $HeldOrdersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HeldOrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HeldOrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HeldOrdersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<String> cartJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HeldOrdersCompanion(
            id: id,
            label: label,
            cartJson: cartJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String label,
            required String cartJson,
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HeldOrdersCompanion.insert(
            id: id,
            label: label,
            cartJson: cartJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HeldOrdersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $HeldOrdersTable,
    HeldOrder,
    $$HeldOrdersTableFilterComposer,
    $$HeldOrdersTableOrderingComposer,
    $$HeldOrdersTableAnnotationComposer,
    $$HeldOrdersTableCreateCompanionBuilder,
    $$HeldOrdersTableUpdateCompanionBuilder,
    (HeldOrder, BaseReferences<_$AppDatabase, $HeldOrdersTable, HeldOrder>),
    HeldOrder,
    PrefetchHooks Function()>;
typedef $$StockLedgerTableCreateCompanionBuilder = StockLedgerCompanion
    Function({
  required String id,
  required String productUnitId,
  required String type,
  required double qtyChange,
  required double stockAfter,
  Value<String?> referenceId,
  Value<String?> kasirId,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});
typedef $$StockLedgerTableUpdateCompanionBuilder = StockLedgerCompanion
    Function({
  Value<String> id,
  Value<String> productUnitId,
  Value<String> type,
  Value<double> qtyChange,
  Value<double> stockAfter,
  Value<String?> referenceId,
  Value<String?> kasirId,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});

class $$StockLedgerTableFilterComposer
    extends Composer<_$AppDatabase, $StockLedgerTable> {
  $$StockLedgerTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get qtyChange => $composableBuilder(
      column: $table.qtyChange, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get stockAfter => $composableBuilder(
      column: $table.stockAfter, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$StockLedgerTableOrderingComposer
    extends Composer<_$AppDatabase, $StockLedgerTable> {
  $$StockLedgerTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get qtyChange => $composableBuilder(
      column: $table.qtyChange, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get stockAfter => $composableBuilder(
      column: $table.stockAfter, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$StockLedgerTableAnnotationComposer
    extends Composer<_$AppDatabase, $StockLedgerTable> {
  $$StockLedgerTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get qtyChange =>
      $composableBuilder(column: $table.qtyChange, builder: (column) => column);

  GeneratedColumn<double> get stockAfter => $composableBuilder(
      column: $table.stockAfter, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<String> get kasirId =>
      $composableBuilder(column: $table.kasirId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$StockLedgerTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StockLedgerTable,
    StockLedgerData,
    $$StockLedgerTableFilterComposer,
    $$StockLedgerTableOrderingComposer,
    $$StockLedgerTableAnnotationComposer,
    $$StockLedgerTableCreateCompanionBuilder,
    $$StockLedgerTableUpdateCompanionBuilder,
    (
      StockLedgerData,
      BaseReferences<_$AppDatabase, $StockLedgerTable, StockLedgerData>
    ),
    StockLedgerData,
    PrefetchHooks Function()> {
  $$StockLedgerTableTableManager(_$AppDatabase db, $StockLedgerTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockLedgerTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockLedgerTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockLedgerTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> qtyChange = const Value.absent(),
            Value<double> stockAfter = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StockLedgerCompanion(
            id: id,
            productUnitId: productUnitId,
            type: type,
            qtyChange: qtyChange,
            stockAfter: stockAfter,
            referenceId: referenceId,
            kasirId: kasirId,
            note: note,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productUnitId,
            required String type,
            required double qtyChange,
            required double stockAfter,
            Value<String?> referenceId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StockLedgerCompanion.insert(
            id: id,
            productUnitId: productUnitId,
            type: type,
            qtyChange: qtyChange,
            stockAfter: stockAfter,
            referenceId: referenceId,
            kasirId: kasirId,
            note: note,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StockLedgerTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StockLedgerTable,
    StockLedgerData,
    $$StockLedgerTableFilterComposer,
    $$StockLedgerTableOrderingComposer,
    $$StockLedgerTableAnnotationComposer,
    $$StockLedgerTableCreateCompanionBuilder,
    $$StockLedgerTableUpdateCompanionBuilder,
    (
      StockLedgerData,
      BaseReferences<_$AppDatabase, $StockLedgerTable, StockLedgerData>
    ),
    StockLedgerData,
    PrefetchHooks Function()>;
typedef $$ExpensesTableCreateCompanionBuilder = ExpensesCompanion Function({
  required String id,
  required String localId,
  required String type,
  required int amount,
  Value<String?> note,
  Value<String?> referenceId,
  Value<String?> kasirId,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});
typedef $$ExpensesTableUpdateCompanionBuilder = ExpensesCompanion Function({
  Value<String> id,
  Value<String> localId,
  Value<String> type,
  Value<int> amount,
  Value<String?> note,
  Value<String?> referenceId,
  Value<String?> kasirId,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<String> get kasirId =>
      $composableBuilder(column: $table.kasirId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$ExpensesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExpensesTable,
    Expense,
    $$ExpensesTableFilterComposer,
    $$ExpensesTableOrderingComposer,
    $$ExpensesTableAnnotationComposer,
    $$ExpensesTableCreateCompanionBuilder,
    $$ExpensesTableUpdateCompanionBuilder,
    (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
    Expense,
    PrefetchHooks Function()> {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> localId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> amount = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpensesCompanion(
            id: id,
            localId: localId,
            type: type,
            amount: amount,
            note: note,
            referenceId: referenceId,
            kasirId: kasirId,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String localId,
            required String type,
            required int amount,
            Value<String?> note = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpensesCompanion.insert(
            id: id,
            localId: localId,
            type: type,
            amount: amount,
            note: note,
            referenceId: referenceId,
            kasirId: kasirId,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExpensesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ExpensesTable,
    Expense,
    $$ExpensesTableFilterComposer,
    $$ExpensesTableOrderingComposer,
    $$ExpensesTableAnnotationComposer,
    $$ExpensesTableCreateCompanionBuilder,
    $$ExpensesTableUpdateCompanionBuilder,
    (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
    Expense,
    PrefetchHooks Function()>;
typedef $$LoyaltyPointLedgerTableCreateCompanionBuilder
    = LoyaltyPointLedgerCompanion Function({
  required String id,
  required String customerId,
  required String type,
  required int points,
  Value<String?> referenceId,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});
typedef $$LoyaltyPointLedgerTableUpdateCompanionBuilder
    = LoyaltyPointLedgerCompanion Function({
  Value<String> id,
  Value<String> customerId,
  Value<String> type,
  Value<int> points,
  Value<String?> referenceId,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});

class $$LoyaltyPointLedgerTableFilterComposer
    extends Composer<_$AppDatabase, $LoyaltyPointLedgerTable> {
  $$LoyaltyPointLedgerTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get points => $composableBuilder(
      column: $table.points, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$LoyaltyPointLedgerTableOrderingComposer
    extends Composer<_$AppDatabase, $LoyaltyPointLedgerTable> {
  $$LoyaltyPointLedgerTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get points => $composableBuilder(
      column: $table.points, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$LoyaltyPointLedgerTableAnnotationComposer
    extends Composer<_$AppDatabase, $LoyaltyPointLedgerTable> {
  $$LoyaltyPointLedgerTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get points =>
      $composableBuilder(column: $table.points, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$LoyaltyPointLedgerTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LoyaltyPointLedgerTable,
    LoyaltyPointLedgerData,
    $$LoyaltyPointLedgerTableFilterComposer,
    $$LoyaltyPointLedgerTableOrderingComposer,
    $$LoyaltyPointLedgerTableAnnotationComposer,
    $$LoyaltyPointLedgerTableCreateCompanionBuilder,
    $$LoyaltyPointLedgerTableUpdateCompanionBuilder,
    (
      LoyaltyPointLedgerData,
      BaseReferences<_$AppDatabase, $LoyaltyPointLedgerTable,
          LoyaltyPointLedgerData>
    ),
    LoyaltyPointLedgerData,
    PrefetchHooks Function()> {
  $$LoyaltyPointLedgerTableTableManager(
      _$AppDatabase db, $LoyaltyPointLedgerTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoyaltyPointLedgerTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoyaltyPointLedgerTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoyaltyPointLedgerTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> customerId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> points = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LoyaltyPointLedgerCompanion(
            id: id,
            customerId: customerId,
            type: type,
            points: points,
            referenceId: referenceId,
            note: note,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String customerId,
            required String type,
            required int points,
            Value<String?> referenceId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LoyaltyPointLedgerCompanion.insert(
            id: id,
            customerId: customerId,
            type: type,
            points: points,
            referenceId: referenceId,
            note: note,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LoyaltyPointLedgerTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LoyaltyPointLedgerTable,
    LoyaltyPointLedgerData,
    $$LoyaltyPointLedgerTableFilterComposer,
    $$LoyaltyPointLedgerTableOrderingComposer,
    $$LoyaltyPointLedgerTableAnnotationComposer,
    $$LoyaltyPointLedgerTableCreateCompanionBuilder,
    $$LoyaltyPointLedgerTableUpdateCompanionBuilder,
    (
      LoyaltyPointLedgerData,
      BaseReferences<_$AppDatabase, $LoyaltyPointLedgerTable,
          LoyaltyPointLedgerData>
    ),
    LoyaltyPointLedgerData,
    PrefetchHooks Function()>;
typedef $$SuppliersTableCreateCompanionBuilder = SuppliersCompanion Function({
  required String id,
  required String name,
  Value<String?> phone,
  Value<int> outstandingDebt,
  Value<String?> notes,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$SuppliersTableUpdateCompanionBuilder = SuppliersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> phone,
  Value<int> outstandingDebt,
  Value<String?> notes,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$SuppliersTableFilterComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get outstandingDebt => $composableBuilder(
      column: $table.outstandingDebt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$SuppliersTableOrderingComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get outstandingDebt => $composableBuilder(
      column: $table.outstandingDebt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$SuppliersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<int> get outstandingDebt => $composableBuilder(
      column: $table.outstandingDebt, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SuppliersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SuppliersTable,
    Supplier,
    $$SuppliersTableFilterComposer,
    $$SuppliersTableOrderingComposer,
    $$SuppliersTableAnnotationComposer,
    $$SuppliersTableCreateCompanionBuilder,
    $$SuppliersTableUpdateCompanionBuilder,
    (Supplier, BaseReferences<_$AppDatabase, $SuppliersTable, Supplier>),
    Supplier,
    PrefetchHooks Function()> {
  $$SuppliersTableTableManager(_$AppDatabase db, $SuppliersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SuppliersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SuppliersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SuppliersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<int> outstandingDebt = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SuppliersCompanion(
            id: id,
            name: name,
            phone: phone,
            outstandingDebt: outstandingDebt,
            notes: notes,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> phone = const Value.absent(),
            Value<int> outstandingDebt = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SuppliersCompanion.insert(
            id: id,
            name: name,
            phone: phone,
            outstandingDebt: outstandingDebt,
            notes: notes,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SuppliersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SuppliersTable,
    Supplier,
    $$SuppliersTableFilterComposer,
    $$SuppliersTableOrderingComposer,
    $$SuppliersTableAnnotationComposer,
    $$SuppliersTableCreateCompanionBuilder,
    $$SuppliersTableUpdateCompanionBuilder,
    (Supplier, BaseReferences<_$AppDatabase, $SuppliersTable, Supplier>),
    Supplier,
    PrefetchHooks Function()>;
typedef $$PurchasesTableCreateCompanionBuilder = PurchasesCompanion Function({
  required String id,
  required String localId,
  Value<String?> supplierId,
  Value<String?> kasirId,
  required String status,
  Value<int> total,
  Value<int> paid,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});
typedef $$PurchasesTableUpdateCompanionBuilder = PurchasesCompanion Function({
  Value<String> id,
  Value<String> localId,
  Value<String?> supplierId,
  Value<String?> kasirId,
  Value<String> status,
  Value<int> total,
  Value<int> paid,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});

final class $$PurchasesTableReferences
    extends BaseReferences<_$AppDatabase, $PurchasesTable, Purchase> {
  $$PurchasesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PurchaseItemsTable, List<PurchaseItem>>
      _purchaseItemsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.purchaseItems,
              aliasName: $_aliasNameGenerator(
                  db.purchases.id, db.purchaseItems.purchaseId));

  $$PurchaseItemsTableProcessedTableManager get purchaseItemsRefs {
    final manager = $$PurchaseItemsTableTableManager($_db, $_db.purchaseItems)
        .filter((f) => f.purchaseId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_purchaseItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$PurchasesTableFilterComposer
    extends Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get supplierId => $composableBuilder(
      column: $table.supplierId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get paid => $composableBuilder(
      column: $table.paid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> purchaseItemsRefs(
      Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f) {
    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.purchaseItems,
        getReferencedColumn: (t) => t.purchaseId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PurchaseItemsTableFilterComposer(
              $db: $db,
              $table: $db.purchaseItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PurchasesTableOrderingComposer
    extends Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get supplierId => $composableBuilder(
      column: $table.supplierId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kasirId => $composableBuilder(
      column: $table.kasirId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get paid => $composableBuilder(
      column: $table.paid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$PurchasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get supplierId => $composableBuilder(
      column: $table.supplierId, builder: (column) => column);

  GeneratedColumn<String> get kasirId =>
      $composableBuilder(column: $table.kasirId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<int> get paid =>
      $composableBuilder(column: $table.paid, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  Expression<T> purchaseItemsRefs<T extends Object>(
      Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f) {
    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.purchaseItems,
        getReferencedColumn: (t) => t.purchaseId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PurchaseItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.purchaseItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PurchasesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PurchasesTable,
    Purchase,
    $$PurchasesTableFilterComposer,
    $$PurchasesTableOrderingComposer,
    $$PurchasesTableAnnotationComposer,
    $$PurchasesTableCreateCompanionBuilder,
    $$PurchasesTableUpdateCompanionBuilder,
    (Purchase, $$PurchasesTableReferences),
    Purchase,
    PrefetchHooks Function({bool purchaseItemsRefs})> {
  $$PurchasesTableTableManager(_$AppDatabase db, $PurchasesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> localId = const Value.absent(),
            Value<String?> supplierId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> total = const Value.absent(),
            Value<int> paid = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PurchasesCompanion(
            id: id,
            localId: localId,
            supplierId: supplierId,
            kasirId: kasirId,
            status: status,
            total: total,
            paid: paid,
            note: note,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String localId,
            Value<String?> supplierId = const Value.absent(),
            Value<String?> kasirId = const Value.absent(),
            required String status,
            Value<int> total = const Value.absent(),
            Value<int> paid = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PurchasesCompanion.insert(
            id: id,
            localId: localId,
            supplierId: supplierId,
            kasirId: kasirId,
            status: status,
            total: total,
            paid: paid,
            note: note,
            createdAt: createdAt,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PurchasesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({purchaseItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (purchaseItemsRefs) db.purchaseItems
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (purchaseItemsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$PurchasesTableReferences
                            ._purchaseItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$PurchasesTableReferences(db, table, p0)
                                .purchaseItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.purchaseId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$PurchasesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PurchasesTable,
    Purchase,
    $$PurchasesTableFilterComposer,
    $$PurchasesTableOrderingComposer,
    $$PurchasesTableAnnotationComposer,
    $$PurchasesTableCreateCompanionBuilder,
    $$PurchasesTableUpdateCompanionBuilder,
    (Purchase, $$PurchasesTableReferences),
    Purchase,
    PrefetchHooks Function({bool purchaseItemsRefs})>;
typedef $$PurchaseItemsTableCreateCompanionBuilder = PurchaseItemsCompanion
    Function({
  required String id,
  required String purchaseId,
  required String productUnitId,
  required double qty,
  required int pricePerUnit,
  required int subtotal,
  Value<int> rowid,
});
typedef $$PurchaseItemsTableUpdateCompanionBuilder = PurchaseItemsCompanion
    Function({
  Value<String> id,
  Value<String> purchaseId,
  Value<String> productUnitId,
  Value<double> qty,
  Value<int> pricePerUnit,
  Value<int> subtotal,
  Value<int> rowid,
});

final class $$PurchaseItemsTableReferences
    extends BaseReferences<_$AppDatabase, $PurchaseItemsTable, PurchaseItem> {
  $$PurchaseItemsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $PurchasesTable _purchaseIdTable(_$AppDatabase db) =>
      db.purchases.createAlias(
          $_aliasNameGenerator(db.purchaseItems.purchaseId, db.purchases.id));

  $$PurchasesTableProcessedTableManager get purchaseId {
    final manager = $$PurchasesTableTableManager($_db, $_db.purchases)
        .filter((f) => f.id($_item.purchaseId));
    final item = $_typedResult.readTableOrNull(_purchaseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$PurchaseItemsTableFilterComposer
    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
  $$PurchaseItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get qty => $composableBuilder(
      column: $table.qty, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pricePerUnit => $composableBuilder(
      column: $table.pricePerUnit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get subtotal => $composableBuilder(
      column: $table.subtotal, builder: (column) => ColumnFilters(column));

  $$PurchasesTableFilterComposer get purchaseId {
    final $$PurchasesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.purchaseId,
        referencedTable: $db.purchases,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PurchasesTableFilterComposer(
              $db: $db,
              $table: $db.purchases,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PurchaseItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
  $$PurchaseItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get qty => $composableBuilder(
      column: $table.qty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pricePerUnit => $composableBuilder(
      column: $table.pricePerUnit,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get subtotal => $composableBuilder(
      column: $table.subtotal, builder: (column) => ColumnOrderings(column));

  $$PurchasesTableOrderingComposer get purchaseId {
    final $$PurchasesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.purchaseId,
        referencedTable: $db.purchases,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PurchasesTableOrderingComposer(
              $db: $db,
              $table: $db.purchases,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PurchaseItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
  $$PurchaseItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productUnitId => $composableBuilder(
      column: $table.productUnitId, builder: (column) => column);

  GeneratedColumn<double> get qty =>
      $composableBuilder(column: $table.qty, builder: (column) => column);

  GeneratedColumn<int> get pricePerUnit => $composableBuilder(
      column: $table.pricePerUnit, builder: (column) => column);

  GeneratedColumn<int> get subtotal =>
      $composableBuilder(column: $table.subtotal, builder: (column) => column);

  $$PurchasesTableAnnotationComposer get purchaseId {
    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.purchaseId,
        referencedTable: $db.purchases,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PurchasesTableAnnotationComposer(
              $db: $db,
              $table: $db.purchases,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PurchaseItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PurchaseItemsTable,
    PurchaseItem,
    $$PurchaseItemsTableFilterComposer,
    $$PurchaseItemsTableOrderingComposer,
    $$PurchaseItemsTableAnnotationComposer,
    $$PurchaseItemsTableCreateCompanionBuilder,
    $$PurchaseItemsTableUpdateCompanionBuilder,
    (PurchaseItem, $$PurchaseItemsTableReferences),
    PurchaseItem,
    PrefetchHooks Function({bool purchaseId})> {
  $$PurchaseItemsTableTableManager(_$AppDatabase db, $PurchaseItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchaseItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchaseItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchaseItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> purchaseId = const Value.absent(),
            Value<String> productUnitId = const Value.absent(),
            Value<double> qty = const Value.absent(),
            Value<int> pricePerUnit = const Value.absent(),
            Value<int> subtotal = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PurchaseItemsCompanion(
            id: id,
            purchaseId: purchaseId,
            productUnitId: productUnitId,
            qty: qty,
            pricePerUnit: pricePerUnit,
            subtotal: subtotal,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String purchaseId,
            required String productUnitId,
            required double qty,
            required int pricePerUnit,
            required int subtotal,
            Value<int> rowid = const Value.absent(),
          }) =>
              PurchaseItemsCompanion.insert(
            id: id,
            purchaseId: purchaseId,
            productUnitId: productUnitId,
            qty: qty,
            pricePerUnit: pricePerUnit,
            subtotal: subtotal,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PurchaseItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({purchaseId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (purchaseId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.purchaseId,
                    referencedTable:
                        $$PurchaseItemsTableReferences._purchaseIdTable(db),
                    referencedColumn:
                        $$PurchaseItemsTableReferences._purchaseIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$PurchaseItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PurchaseItemsTable,
    PurchaseItem,
    $$PurchaseItemsTableFilterComposer,
    $$PurchaseItemsTableOrderingComposer,
    $$PurchaseItemsTableAnnotationComposer,
    $$PurchaseItemsTableCreateCompanionBuilder,
    $$PurchaseItemsTableUpdateCompanionBuilder,
    (PurchaseItem, $$PurchaseItemsTableReferences),
    PurchaseItem,
    PrefetchHooks Function({bool purchaseId})>;
typedef $$KasirPermissionsTableCreateCompanionBuilder
    = KasirPermissionsCompanion Function({
  required String permissionKey,
  Value<bool> isEnabled,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$KasirPermissionsTableUpdateCompanionBuilder
    = KasirPermissionsCompanion Function({
  Value<String> permissionKey,
  Value<bool> isEnabled,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$KasirPermissionsTableFilterComposer
    extends Composer<_$AppDatabase, $KasirPermissionsTable> {
  $$KasirPermissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get permissionKey => $composableBuilder(
      column: $table.permissionKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$KasirPermissionsTableOrderingComposer
    extends Composer<_$AppDatabase, $KasirPermissionsTable> {
  $$KasirPermissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get permissionKey => $composableBuilder(
      column: $table.permissionKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$KasirPermissionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KasirPermissionsTable> {
  $$KasirPermissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get permissionKey => $composableBuilder(
      column: $table.permissionKey, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KasirPermissionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KasirPermissionsTable,
    KasirPermission,
    $$KasirPermissionsTableFilterComposer,
    $$KasirPermissionsTableOrderingComposer,
    $$KasirPermissionsTableAnnotationComposer,
    $$KasirPermissionsTableCreateCompanionBuilder,
    $$KasirPermissionsTableUpdateCompanionBuilder,
    (
      KasirPermission,
      BaseReferences<_$AppDatabase, $KasirPermissionsTable, KasirPermission>
    ),
    KasirPermission,
    PrefetchHooks Function()> {
  $$KasirPermissionsTableTableManager(
      _$AppDatabase db, $KasirPermissionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KasirPermissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KasirPermissionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KasirPermissionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> permissionKey = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KasirPermissionsCompanion(
            permissionKey: permissionKey,
            isEnabled: isEnabled,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String permissionKey,
            Value<bool> isEnabled = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KasirPermissionsCompanion.insert(
            permissionKey: permissionKey,
            isEnabled: isEnabled,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KasirPermissionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KasirPermissionsTable,
    KasirPermission,
    $$KasirPermissionsTableFilterComposer,
    $$KasirPermissionsTableOrderingComposer,
    $$KasirPermissionsTableAnnotationComposer,
    $$KasirPermissionsTableCreateCompanionBuilder,
    $$KasirPermissionsTableUpdateCompanionBuilder,
    (
      KasirPermission,
      BaseReferences<_$AppDatabase, $KasirPermissionsTable, KasirPermission>
    ),
    KasirPermission,
    PrefetchHooks Function()>;
typedef $$PaymentMethodsTableCreateCompanionBuilder = PaymentMethodsCompanion
    Function({
  required String id,
  required String type,
  required String name,
  Value<String?> data,
  Value<String?> qrValue,
  Value<bool> isActive,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$PaymentMethodsTableUpdateCompanionBuilder = PaymentMethodsCompanion
    Function({
  Value<String> id,
  Value<String> type,
  Value<String> name,
  Value<String?> data,
  Value<String?> qrValue,
  Value<bool> isActive,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$PaymentMethodsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get qrValue => $composableBuilder(
      column: $table.qrValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));
}

class $$PaymentMethodsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get qrValue => $composableBuilder(
      column: $table.qrValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));
}

class $$PaymentMethodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get qrValue =>
      $composableBuilder(column: $table.qrValue, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$PaymentMethodsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PaymentMethodsTable,
    PaymentMethod,
    $$PaymentMethodsTableFilterComposer,
    $$PaymentMethodsTableOrderingComposer,
    $$PaymentMethodsTableAnnotationComposer,
    $$PaymentMethodsTableCreateCompanionBuilder,
    $$PaymentMethodsTableUpdateCompanionBuilder,
    (
      PaymentMethod,
      BaseReferences<_$AppDatabase, $PaymentMethodsTable, PaymentMethod>
    ),
    PaymentMethod,
    PrefetchHooks Function()> {
  $$PaymentMethodsTableTableManager(
      _$AppDatabase db, $PaymentMethodsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentMethodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentMethodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentMethodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> data = const Value.absent(),
            Value<String?> qrValue = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PaymentMethodsCompanion(
            id: id,
            type: type,
            name: name,
            data: data,
            qrValue: qrValue,
            isActive: isActive,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            required String name,
            Value<String?> data = const Value.absent(),
            Value<String?> qrValue = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PaymentMethodsCompanion.insert(
            id: id,
            type: type,
            name: name,
            data: data,
            qrValue: qrValue,
            isActive: isActive,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PaymentMethodsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PaymentMethodsTable,
    PaymentMethod,
    $$PaymentMethodsTableFilterComposer,
    $$PaymentMethodsTableOrderingComposer,
    $$PaymentMethodsTableAnnotationComposer,
    $$PaymentMethodsTableCreateCompanionBuilder,
    $$PaymentMethodsTableUpdateCompanionBuilder,
    (
      PaymentMethod,
      BaseReferences<_$AppDatabase, $PaymentMethodsTable, PaymentMethod>
    ),
    PaymentMethod,
    PrefetchHooks Function()>;
typedef $$DailySummariesTableCreateCompanionBuilder = DailySummariesCompanion
    Function({
  required String date,
  Value<int> omzet,
  Value<int> hpp,
  Value<int> labaKotor,
  Value<int> jumlahTransaksi,
  Value<int> jumlahItem,
  Value<int> pembayaranTunai,
  Value<int> pembayaranQris,
  Value<int> pembayaranTransfer,
  Value<int> pembayaranLainnya,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$DailySummariesTableUpdateCompanionBuilder = DailySummariesCompanion
    Function({
  Value<String> date,
  Value<int> omzet,
  Value<int> hpp,
  Value<int> labaKotor,
  Value<int> jumlahTransaksi,
  Value<int> jumlahItem,
  Value<int> pembayaranTunai,
  Value<int> pembayaranQris,
  Value<int> pembayaranTransfer,
  Value<int> pembayaranLainnya,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$DailySummariesTableFilterComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get omzet => $composableBuilder(
      column: $table.omzet, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get hpp => $composableBuilder(
      column: $table.hpp, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get labaKotor => $composableBuilder(
      column: $table.labaKotor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get jumlahTransaksi => $composableBuilder(
      column: $table.jumlahTransaksi,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get jumlahItem => $composableBuilder(
      column: $table.jumlahItem, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pembayaranTunai => $composableBuilder(
      column: $table.pembayaranTunai,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pembayaranQris => $composableBuilder(
      column: $table.pembayaranQris,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pembayaranTransfer => $composableBuilder(
      column: $table.pembayaranTransfer,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pembayaranLainnya => $composableBuilder(
      column: $table.pembayaranLainnya,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$DailySummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get omzet => $composableBuilder(
      column: $table.omzet, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get hpp => $composableBuilder(
      column: $table.hpp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get labaKotor => $composableBuilder(
      column: $table.labaKotor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get jumlahTransaksi => $composableBuilder(
      column: $table.jumlahTransaksi,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get jumlahItem => $composableBuilder(
      column: $table.jumlahItem, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pembayaranTunai => $composableBuilder(
      column: $table.pembayaranTunai,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pembayaranQris => $composableBuilder(
      column: $table.pembayaranQris,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pembayaranTransfer => $composableBuilder(
      column: $table.pembayaranTransfer,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pembayaranLainnya => $composableBuilder(
      column: $table.pembayaranLainnya,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$DailySummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get omzet =>
      $composableBuilder(column: $table.omzet, builder: (column) => column);

  GeneratedColumn<int> get hpp =>
      $composableBuilder(column: $table.hpp, builder: (column) => column);

  GeneratedColumn<int> get labaKotor =>
      $composableBuilder(column: $table.labaKotor, builder: (column) => column);

  GeneratedColumn<int> get jumlahTransaksi => $composableBuilder(
      column: $table.jumlahTransaksi, builder: (column) => column);

  GeneratedColumn<int> get jumlahItem => $composableBuilder(
      column: $table.jumlahItem, builder: (column) => column);

  GeneratedColumn<int> get pembayaranTunai => $composableBuilder(
      column: $table.pembayaranTunai, builder: (column) => column);

  GeneratedColumn<int> get pembayaranQris => $composableBuilder(
      column: $table.pembayaranQris, builder: (column) => column);

  GeneratedColumn<int> get pembayaranTransfer => $composableBuilder(
      column: $table.pembayaranTransfer, builder: (column) => column);

  GeneratedColumn<int> get pembayaranLainnya => $composableBuilder(
      column: $table.pembayaranLainnya, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DailySummariesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DailySummariesTable,
    DailySummary,
    $$DailySummariesTableFilterComposer,
    $$DailySummariesTableOrderingComposer,
    $$DailySummariesTableAnnotationComposer,
    $$DailySummariesTableCreateCompanionBuilder,
    $$DailySummariesTableUpdateCompanionBuilder,
    (
      DailySummary,
      BaseReferences<_$AppDatabase, $DailySummariesTable, DailySummary>
    ),
    DailySummary,
    PrefetchHooks Function()> {
  $$DailySummariesTableTableManager(
      _$AppDatabase db, $DailySummariesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailySummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailySummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailySummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> date = const Value.absent(),
            Value<int> omzet = const Value.absent(),
            Value<int> hpp = const Value.absent(),
            Value<int> labaKotor = const Value.absent(),
            Value<int> jumlahTransaksi = const Value.absent(),
            Value<int> jumlahItem = const Value.absent(),
            Value<int> pembayaranTunai = const Value.absent(),
            Value<int> pembayaranQris = const Value.absent(),
            Value<int> pembayaranTransfer = const Value.absent(),
            Value<int> pembayaranLainnya = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DailySummariesCompanion(
            date: date,
            omzet: omzet,
            hpp: hpp,
            labaKotor: labaKotor,
            jumlahTransaksi: jumlahTransaksi,
            jumlahItem: jumlahItem,
            pembayaranTunai: pembayaranTunai,
            pembayaranQris: pembayaranQris,
            pembayaranTransfer: pembayaranTransfer,
            pembayaranLainnya: pembayaranLainnya,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String date,
            Value<int> omzet = const Value.absent(),
            Value<int> hpp = const Value.absent(),
            Value<int> labaKotor = const Value.absent(),
            Value<int> jumlahTransaksi = const Value.absent(),
            Value<int> jumlahItem = const Value.absent(),
            Value<int> pembayaranTunai = const Value.absent(),
            Value<int> pembayaranQris = const Value.absent(),
            Value<int> pembayaranTransfer = const Value.absent(),
            Value<int> pembayaranLainnya = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DailySummariesCompanion.insert(
            date: date,
            omzet: omzet,
            hpp: hpp,
            labaKotor: labaKotor,
            jumlahTransaksi: jumlahTransaksi,
            jumlahItem: jumlahItem,
            pembayaranTunai: pembayaranTunai,
            pembayaranQris: pembayaranQris,
            pembayaranTransfer: pembayaranTransfer,
            pembayaranLainnya: pembayaranLainnya,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DailySummariesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DailySummariesTable,
    DailySummary,
    $$DailySummariesTableFilterComposer,
    $$DailySummariesTableOrderingComposer,
    $$DailySummariesTableAnnotationComposer,
    $$DailySummariesTableCreateCompanionBuilder,
    $$DailySummariesTableUpdateCompanionBuilder,
    (
      DailySummary,
      BaseReferences<_$AppDatabase, $DailySummariesTable, DailySummary>
    ),
    DailySummary,
    PrefetchHooks Function()>;
typedef $$EmployeesTableCreateCompanionBuilder = EmployeesCompanion Function({
  required String id,
  required String name,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$EmployeesTableUpdateCompanionBuilder = EmployeesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$EmployeesTableFilterComposer
    extends Composer<_$AppDatabase, $EmployeesTable> {
  $$EmployeesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$EmployeesTableOrderingComposer
    extends Composer<_$AppDatabase, $EmployeesTable> {
  $$EmployeesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$EmployeesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmployeesTable> {
  $$EmployeesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EmployeesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $EmployeesTable,
    Employee,
    $$EmployeesTableFilterComposer,
    $$EmployeesTableOrderingComposer,
    $$EmployeesTableAnnotationComposer,
    $$EmployeesTableCreateCompanionBuilder,
    $$EmployeesTableUpdateCompanionBuilder,
    (Employee, BaseReferences<_$AppDatabase, $EmployeesTable, Employee>),
    Employee,
    PrefetchHooks Function()> {
  $$EmployeesTableTableManager(_$AppDatabase db, $EmployeesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmployeesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmployeesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmployeesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EmployeesCompanion(
            id: id,
            name: name,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EmployeesCompanion.insert(
            id: id,
            name: name,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EmployeesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $EmployeesTable,
    Employee,
    $$EmployeesTableFilterComposer,
    $$EmployeesTableOrderingComposer,
    $$EmployeesTableAnnotationComposer,
    $$EmployeesTableCreateCompanionBuilder,
    $$EmployeesTableUpdateCompanionBuilder,
    (Employee, BaseReferences<_$AppDatabase, $EmployeesTable, Employee>),
    Employee,
    PrefetchHooks Function()>;
typedef $$CashClosingsTableCreateCompanionBuilder = CashClosingsCompanion
    Function({
  required String id,
  required String date,
  Value<String?> deviceCode,
  required int systemCash,
  Value<int> systemNonCash,
  Value<int> txCount,
  required int physicalCash,
  required int difference,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$CashClosingsTableUpdateCompanionBuilder = CashClosingsCompanion
    Function({
  Value<String> id,
  Value<String> date,
  Value<String?> deviceCode,
  Value<int> systemCash,
  Value<int> systemNonCash,
  Value<int> txCount,
  Value<int> physicalCash,
  Value<int> difference,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$CashClosingsTableFilterComposer
    extends Composer<_$AppDatabase, $CashClosingsTable> {
  $$CashClosingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceCode => $composableBuilder(
      column: $table.deviceCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get systemCash => $composableBuilder(
      column: $table.systemCash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get systemNonCash => $composableBuilder(
      column: $table.systemNonCash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get txCount => $composableBuilder(
      column: $table.txCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get physicalCash => $composableBuilder(
      column: $table.physicalCash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get difference => $composableBuilder(
      column: $table.difference, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$CashClosingsTableOrderingComposer
    extends Composer<_$AppDatabase, $CashClosingsTable> {
  $$CashClosingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceCode => $composableBuilder(
      column: $table.deviceCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get systemCash => $composableBuilder(
      column: $table.systemCash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get systemNonCash => $composableBuilder(
      column: $table.systemNonCash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get txCount => $composableBuilder(
      column: $table.txCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get physicalCash => $composableBuilder(
      column: $table.physicalCash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get difference => $composableBuilder(
      column: $table.difference, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$CashClosingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CashClosingsTable> {
  $$CashClosingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get deviceCode => $composableBuilder(
      column: $table.deviceCode, builder: (column) => column);

  GeneratedColumn<int> get systemCash => $composableBuilder(
      column: $table.systemCash, builder: (column) => column);

  GeneratedColumn<int> get systemNonCash => $composableBuilder(
      column: $table.systemNonCash, builder: (column) => column);

  GeneratedColumn<int> get txCount =>
      $composableBuilder(column: $table.txCount, builder: (column) => column);

  GeneratedColumn<int> get physicalCash => $composableBuilder(
      column: $table.physicalCash, builder: (column) => column);

  GeneratedColumn<int> get difference => $composableBuilder(
      column: $table.difference, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CashClosingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CashClosingsTable,
    CashClosing,
    $$CashClosingsTableFilterComposer,
    $$CashClosingsTableOrderingComposer,
    $$CashClosingsTableAnnotationComposer,
    $$CashClosingsTableCreateCompanionBuilder,
    $$CashClosingsTableUpdateCompanionBuilder,
    (
      CashClosing,
      BaseReferences<_$AppDatabase, $CashClosingsTable, CashClosing>
    ),
    CashClosing,
    PrefetchHooks Function()> {
  $$CashClosingsTableTableManager(_$AppDatabase db, $CashClosingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashClosingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashClosingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CashClosingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> date = const Value.absent(),
            Value<String?> deviceCode = const Value.absent(),
            Value<int> systemCash = const Value.absent(),
            Value<int> systemNonCash = const Value.absent(),
            Value<int> txCount = const Value.absent(),
            Value<int> physicalCash = const Value.absent(),
            Value<int> difference = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CashClosingsCompanion(
            id: id,
            date: date,
            deviceCode: deviceCode,
            systemCash: systemCash,
            systemNonCash: systemNonCash,
            txCount: txCount,
            physicalCash: physicalCash,
            difference: difference,
            note: note,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String date,
            Value<String?> deviceCode = const Value.absent(),
            required int systemCash,
            Value<int> systemNonCash = const Value.absent(),
            Value<int> txCount = const Value.absent(),
            required int physicalCash,
            required int difference,
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CashClosingsCompanion.insert(
            id: id,
            date: date,
            deviceCode: deviceCode,
            systemCash: systemCash,
            systemNonCash: systemNonCash,
            txCount: txCount,
            physicalCash: physicalCash,
            difference: difference,
            note: note,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CashClosingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CashClosingsTable,
    CashClosing,
    $$CashClosingsTableFilterComposer,
    $$CashClosingsTableOrderingComposer,
    $$CashClosingsTableAnnotationComposer,
    $$CashClosingsTableCreateCompanionBuilder,
    $$CashClosingsTableUpdateCompanionBuilder,
    (
      CashClosing,
      BaseReferences<_$AppDatabase, $CashClosingsTable, CashClosing>
    ),
    CashClosing,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$ProductGroupsTableTableManager get productGroups =>
      $$ProductGroupsTableTableManager(_db, _db.productGroups);
  $$UnitTypesTableTableManager get unitTypes =>
      $$UnitTypesTableTableManager(_db, _db.unitTypes);
  $$ProductUnitsTableTableManager get productUnits =>
      $$ProductUnitsTableTableManager(_db, _db.productUnits);
  $$ProductBarcodesTableTableManager get productBarcodes =>
      $$ProductBarcodesTableTableManager(_db, _db.productBarcodes);
  $$PriceTiersTableTableManager get priceTiers =>
      $$PriceTiersTableTableManager(_db, _db.priceTiers);
  $$AltPricesTableTableManager get altPrices =>
      $$AltPricesTableTableManager(_db, _db.altPrices);
  $$CustomerGroupsTableTableManager get customerGroups =>
      $$CustomerGroupsTableTableManager(_db, _db.customerGroups);
  $$CustomerGroupPricesTableTableManager get customerGroupPrices =>
      $$CustomerGroupPricesTableTableManager(_db, _db.customerGroupPrices);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$TransactionItemsTableTableManager get transactionItems =>
      $$TransactionItemsTableTableManager(_db, _db.transactionItems);
  $$TransactionPaymentsTableTableManager get transactionPayments =>
      $$TransactionPaymentsTableTableManager(_db, _db.transactionPayments);
  $$HeldOrdersTableTableManager get heldOrders =>
      $$HeldOrdersTableTableManager(_db, _db.heldOrders);
  $$StockLedgerTableTableManager get stockLedger =>
      $$StockLedgerTableTableManager(_db, _db.stockLedger);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$LoyaltyPointLedgerTableTableManager get loyaltyPointLedger =>
      $$LoyaltyPointLedgerTableTableManager(_db, _db.loyaltyPointLedger);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db, _db.suppliers);
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db, _db.purchases);
  $$PurchaseItemsTableTableManager get purchaseItems =>
      $$PurchaseItemsTableTableManager(_db, _db.purchaseItems);
  $$KasirPermissionsTableTableManager get kasirPermissions =>
      $$KasirPermissionsTableTableManager(_db, _db.kasirPermissions);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(_db, _db.paymentMethods);
  $$DailySummariesTableTableManager get dailySummaries =>
      $$DailySummariesTableTableManager(_db, _db.dailySummaries);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db, _db.employees);
  $$CashClosingsTableTableManager get cashClosings =>
      $$CashClosingsTableTableManager(_db, _db.cashClosings);
}
