import 'package:drift/drift.dart';

/// Key-value config per device.
///
/// Keys penting:
///   store_uuid, store_key, store_name, store_address, store_phone,
///   device_name, device_code, device_role (owner|kasir|asisten),
///   point_threshold, receipt_note
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
