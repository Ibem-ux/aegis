import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../secure_storage/secure_storage.dart';

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'aegis_chat.db'));

    // Retrieve/Generate DB Key
    final secureStorage = SecureStorage();
    final dbPassphrase = await secureStorage.getOrGenerateDbKey();

    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        // SQLCipher/SQLite3MC Encryption activation before any query runs
        rawDb.execute("PRAGMA key = '$dbPassphrase';");
      },
    );
  });
}
