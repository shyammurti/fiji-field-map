import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:offroad_core/trails.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/native.dart';

part 'storage.g.dart';

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class TrailVersions extends Table {
  TextColumn get revision => text()();
  TextColumn get parent => text().nullable()();
  TextColumn get payload => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {revision};
}

@DriftDatabase(tables: [Settings, TrailVersions])
class ProjectDatabase extends _$ProjectDatabase {
  ProjectDatabase(File file) : super(NativeDatabase.createInBackground(file));
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(trailVersions);
    },
  );
  Future<String> deviceId() => transaction(() async {
    final stored = await readValue('device_id');
    if (stored is String) return stored;
    final id = const Uuid().v4();
    await saveValue('device_id', id);
    return id;
  });
  Future<List<Trail>> trails() async {
    final rows = await customSelect(
      'SELECT a.payload FROM trail_versions a WHERE NOT EXISTS (SELECT 1 FROM trail_versions b WHERE b.parent=a.revision) ORDER BY a.rowid DESC',
    ).get();
    return [
      for (final r in rows)
        Trail.fromJson(jsonDecode(r.read<String>('payload'))),
    ].where((t) => !t.deleted).toList();
  }

  Future<void> saveTrail(Trail t, {bool clearDraft = false}) =>
      transaction(() async {
        await into(trailVersions).insert(
          TrailVersionsCompanion.insert(
            revision: t.rev,
            parent: Value(t.parent),
            payload: jsonEncode(t.toJson()),
          ),
          // A recovered Android journal can retry the same immutable revision.
          mode: InsertMode.insertOrIgnore,
        );
        if (clearDraft) await saveValue('draft', []);
      });
  Future<List<TrailVersion>> pending() =>
      (select(trailVersions)
            ..where((v) => v.synced.equals(false))
            ..orderBy([(v) => OrderingTerm.asc(v.rowId)])
            ..limit(4))
          .get();
  Future<void> applySync(
    List<String> acknowledged,
    List<Trail> remote,
    int cursor,
  ) => transaction(() async {
    for (final t in remote) {
      await into(trailVersions).insert(
        TrailVersionsCompanion.insert(
          revision: t.rev,
          parent: Value(t.parent),
          payload: jsonEncode(t.toJson()),
          synced: const Value(true),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
    if (acknowledged.isNotEmpty)
      await (update(trailVersions)..where((v) => v.revision.isIn(acknowledged)))
          .write(const TrailVersionsCompanion(synced: Value(true)));
    await saveValue('sync_cursor', cursor);
  });

  Future<Object?> readValue(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.valueJson);
  }

  Future<void> saveValue(String key, Object value) async {
    await into(
      settings,
    ).insertOnConflictUpdate(Setting(key: key, valueJson: jsonEncode(value)));
  }
}
