// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage.dart';

// ignore_for_file: type=lint
class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String valueJson;
  const Setting({required this.key, required this.valueJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), valueJson: Value(valueJson));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
    };
  }

  Setting copyWith({String? key, String? valueJson}) =>
      Setting(key: key ?? this.key, valueJson: valueJson ?? this.valueJson);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.valueJson == this.valueJson);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String valueJson,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrailVersionsTable extends TrailVersions
    with TableInfo<$TrailVersionsTable, TrailVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrailVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<String> revision = GeneratedColumn<String>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentMeta = const VerificationMeta('parent');
  @override
  late final GeneratedColumn<String> parent = GeneratedColumn<String>(
    'parent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [revision, parent, payload, synced];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trail_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrailVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('parent')) {
      context.handle(
        _parentMeta,
        parent.isAcceptableOrUnknown(data['parent']!, _parentMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {revision};
  @override
  TrailVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrailVersion(
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision'],
      )!,
      parent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
    );
  }

  @override
  $TrailVersionsTable createAlias(String alias) {
    return $TrailVersionsTable(attachedDatabase, alias);
  }
}

class TrailVersion extends DataClass implements Insertable<TrailVersion> {
  final String revision;
  final String? parent;
  final String payload;
  final bool synced;
  const TrailVersion({
    required this.revision,
    this.parent,
    required this.payload,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['revision'] = Variable<String>(revision);
    if (!nullToAbsent || parent != null) {
      map['parent'] = Variable<String>(parent);
    }
    map['payload'] = Variable<String>(payload);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  TrailVersionsCompanion toCompanion(bool nullToAbsent) {
    return TrailVersionsCompanion(
      revision: Value(revision),
      parent: parent == null && nullToAbsent
          ? const Value.absent()
          : Value(parent),
      payload: Value(payload),
      synced: Value(synced),
    );
  }

  factory TrailVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrailVersion(
      revision: serializer.fromJson<String>(json['revision']),
      parent: serializer.fromJson<String?>(json['parent']),
      payload: serializer.fromJson<String>(json['payload']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'revision': serializer.toJson<String>(revision),
      'parent': serializer.toJson<String?>(parent),
      'payload': serializer.toJson<String>(payload),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  TrailVersion copyWith({
    String? revision,
    Value<String?> parent = const Value.absent(),
    String? payload,
    bool? synced,
  }) => TrailVersion(
    revision: revision ?? this.revision,
    parent: parent.present ? parent.value : this.parent,
    payload: payload ?? this.payload,
    synced: synced ?? this.synced,
  );
  TrailVersion copyWithCompanion(TrailVersionsCompanion data) {
    return TrailVersion(
      revision: data.revision.present ? data.revision.value : this.revision,
      parent: data.parent.present ? data.parent.value : this.parent,
      payload: data.payload.present ? data.payload.value : this.payload,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrailVersion(')
          ..write('revision: $revision, ')
          ..write('parent: $parent, ')
          ..write('payload: $payload, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(revision, parent, payload, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrailVersion &&
          other.revision == this.revision &&
          other.parent == this.parent &&
          other.payload == this.payload &&
          other.synced == this.synced);
}

class TrailVersionsCompanion extends UpdateCompanion<TrailVersion> {
  final Value<String> revision;
  final Value<String?> parent;
  final Value<String> payload;
  final Value<bool> synced;
  final Value<int> rowid;
  const TrailVersionsCompanion({
    this.revision = const Value.absent(),
    this.parent = const Value.absent(),
    this.payload = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrailVersionsCompanion.insert({
    required String revision,
    this.parent = const Value.absent(),
    required String payload,
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : revision = Value(revision),
       payload = Value(payload);
  static Insertable<TrailVersion> custom({
    Expression<String>? revision,
    Expression<String>? parent,
    Expression<String>? payload,
    Expression<bool>? synced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (revision != null) 'revision': revision,
      if (parent != null) 'parent': parent,
      if (payload != null) 'payload': payload,
      if (synced != null) 'synced': synced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrailVersionsCompanion copyWith({
    Value<String>? revision,
    Value<String?>? parent,
    Value<String>? payload,
    Value<bool>? synced,
    Value<int>? rowid,
  }) {
    return TrailVersionsCompanion(
      revision: revision ?? this.revision,
      parent: parent ?? this.parent,
      payload: payload ?? this.payload,
      synced: synced ?? this.synced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (revision.present) {
      map['revision'] = Variable<String>(revision.value);
    }
    if (parent.present) {
      map['parent'] = Variable<String>(parent.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrailVersionsCompanion(')
          ..write('revision: $revision, ')
          ..write('parent: $parent, ')
          ..write('payload: $payload, ')
          ..write('synced: $synced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProjectDatabase extends GeneratedDatabase {
  _$ProjectDatabase(QueryExecutor e) : super(e);
  $ProjectDatabaseManager get managers => $ProjectDatabaseManager(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $TrailVersionsTable trailVersions = $TrailVersionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [settings, trailVersions];
}

typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String valueJson,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> valueJson,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$ProjectDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$ProjectDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$ProjectDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$ProjectDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$ProjectDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$ProjectDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String valueJson,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$ProjectDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$ProjectDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$TrailVersionsTableCreateCompanionBuilder =
    TrailVersionsCompanion Function({
      required String revision,
      Value<String?> parent,
      required String payload,
      Value<bool> synced,
      Value<int> rowid,
    });
typedef $$TrailVersionsTableUpdateCompanionBuilder =
    TrailVersionsCompanion Function({
      Value<String> revision,
      Value<String?> parent,
      Value<String> payload,
      Value<bool> synced,
      Value<int> rowid,
    });

class $$TrailVersionsTableFilterComposer
    extends Composer<_$ProjectDatabase, $TrailVersionsTable> {
  $$TrailVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parent => $composableBuilder(
    column: $table.parent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrailVersionsTableOrderingComposer
    extends Composer<_$ProjectDatabase, $TrailVersionsTable> {
  $$TrailVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parent => $composableBuilder(
    column: $table.parent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrailVersionsTableAnnotationComposer
    extends Composer<_$ProjectDatabase, $TrailVersionsTable> {
  $$TrailVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get parent =>
      $composableBuilder(column: $table.parent, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$TrailVersionsTableTableManager
    extends
        RootTableManager<
          _$ProjectDatabase,
          $TrailVersionsTable,
          TrailVersion,
          $$TrailVersionsTableFilterComposer,
          $$TrailVersionsTableOrderingComposer,
          $$TrailVersionsTableAnnotationComposer,
          $$TrailVersionsTableCreateCompanionBuilder,
          $$TrailVersionsTableUpdateCompanionBuilder,
          (
            TrailVersion,
            BaseReferences<
              _$ProjectDatabase,
              $TrailVersionsTable,
              TrailVersion
            >,
          ),
          TrailVersion,
          PrefetchHooks Function()
        > {
  $$TrailVersionsTableTableManager(
    _$ProjectDatabase db,
    $TrailVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrailVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrailVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrailVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> revision = const Value.absent(),
                Value<String?> parent = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrailVersionsCompanion(
                revision: revision,
                parent: parent,
                payload: payload,
                synced: synced,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String revision,
                Value<String?> parent = const Value.absent(),
                required String payload,
                Value<bool> synced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrailVersionsCompanion.insert(
                revision: revision,
                parent: parent,
                payload: payload,
                synced: synced,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TrailVersionsTable, TrailVersion>(table),
                  BaseReferences<
                    _$ProjectDatabase,
                    $TrailVersionsTable,
                    TrailVersion
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrailVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectDatabase,
      $TrailVersionsTable,
      TrailVersion,
      $$TrailVersionsTableFilterComposer,
      $$TrailVersionsTableOrderingComposer,
      $$TrailVersionsTableAnnotationComposer,
      $$TrailVersionsTableCreateCompanionBuilder,
      $$TrailVersionsTableUpdateCompanionBuilder,
      (
        TrailVersion,
        BaseReferences<_$ProjectDatabase, $TrailVersionsTable, TrailVersion>,
      ),
      TrailVersion,
      PrefetchHooks Function()
    >;

class $ProjectDatabaseManager {
  final _$ProjectDatabase _db;
  $ProjectDatabaseManager(this._db);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$TrailVersionsTableTableManager get trailVersions =>
      $$TrailVersionsTableTableManager(_db, _db.trailVersions);
}
