import 'package:drift/drift.dart';
import 'connection.dart';

part 'local_database.g.dart';

@DataClassName('LocalChat')
class LocalChats extends Table {
  TextColumn get id => text()(); // Chat ID (UUID)
  TextColumn get recipientId => text()();
  TextColumn get recipientUsername => text()();
  TextColumn get recipientDisplayName => text()();
  TextColumn get recipientAvatarUrl => text().nullable()();
  DateTimeColumn get lastMessageAt => dateTime()();
  TextColumn get lastMessagePreview => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LocalMessage')
class LocalMessages extends Table {
  TextColumn get id => text()(); // Message ID (UUID)
  TextColumn get chatId => text().references(LocalChats, #id, onDelete: KeyAction.cascade)();
  TextColumn get senderId => text()();
  TextColumn get content => text()(); // Plaintext decrypted content
  TextColumn get messageType => text()(); // TEXT, IMAGE, VIDEO, AUDIO, FILE
  TextColumn get mediaId => text().nullable()();
  TextColumn get replyToId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text()(); // 'PENDING', 'SYNCED'

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncQueueItem')
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()(); // 'SEND_MESSAGE', 'MARK_READ'
  TextColumn get payload => text()(); // JSON string payload
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [LocalChats, LocalMessages, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  @override
  int get schemaVersion => 1;
}

