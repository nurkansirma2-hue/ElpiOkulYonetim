// Testler Windows'un SQLite kitaplığını yalnız :memory: veritabanında kullanır.
// Kullanıcının veritabanına erişilmez; uygulama bağımlılıkları değişmez.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
// sqflite varsayılan fabrika için bu iç arayüzü zorunlu tutuyor; yalnız testte.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart';

class WindowsMemoryFactory implements SqfliteDatabaseFactory {
  WindowsMemoryDatabase? db;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<String> getDatabasesPath() async => '.';
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final database = db = WindowsMemoryDatabase();
    await options?.onConfigure?.call(database);
    await options?.onCreate?.call(database, options.version!);
    await options?.onOpen?.call(database);
    return database;
  }
}

class WindowsMemoryDatabase implements Database, Transaction {
  final _lib = DynamicLibrary.open('winsqlite3.dll');
  late final _malloc = _lib
      .lookupFunction<
        Pointer<Void> Function(Int32),
        Pointer<Void> Function(int)
      >('sqlite3_malloc');
  late final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('sqlite3_free');
  late final _open = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>),
        int Function(Pointer<Uint8>, Pointer<Pointer<Void>>)
      >('sqlite3_open');
  late final _prepare = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Uint8>,
          Int32,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Uint8>>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Uint8>>,
        )
      >('sqlite3_prepare_v2');
  late final _step = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sqlite3_step');
  late final _finalize = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sqlite3_finalize');
  late final _count = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sqlite3_column_count');
  late final _name = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Int32),
        Pointer<Uint8> Function(Pointer<Void>, int)
      >('sqlite3_column_name');
  late final _type = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sqlite3_column_type');
  late final _integer = _lib
      .lookupFunction<
        Int64 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sqlite3_column_int64');
  late final _double = _lib
      .lookupFunction<
        Double Function(Pointer<Void>, Int32),
        double Function(Pointer<Void>, int)
      >('sqlite3_column_double');
  late final _text = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Int32),
        Pointer<Uint8> Function(Pointer<Void>, int)
      >('sqlite3_column_text');
  late final _blob = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Int32),
        Pointer<Uint8> Function(Pointer<Void>, int)
      >('sqlite3_column_blob');
  late final _bytes = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sqlite3_column_bytes');
  late final _bindBlob = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Int32,
          Pointer<Uint8>,
          Int32,
          Pointer<Void>,
        ),
        int Function(Pointer<Void>, int, Pointer<Uint8>, int, Pointer<Void>)
      >('sqlite3_bind_blob');
  late final _error = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('sqlite3_errmsg');
  late final _close = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sqlite3_close');
  late final _bindText = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Int32,
          Pointer<Uint8>,
          Int32,
          Pointer<Void>,
        ),
        int Function(Pointer<Void>, int, Pointer<Uint8>, int, Pointer<Void>)
      >('sqlite3_bind_text');
  late final _bindInt = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int64),
        int Function(Pointer<Void>, int, int)
      >('sqlite3_bind_int64');
  late final _bindDouble = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Double),
        int Function(Pointer<Void>, int, double)
      >('sqlite3_bind_double');
  late final _lastId = _lib
      .lookupFunction<
        Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sqlite3_last_insert_rowid');
  late final _changes = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sqlite3_changes');
  late final Pointer<Void> _handle;
  int _depth = 0;
  bool _opened = true;

  WindowsMemoryDatabase() {
    final path = _string(':memory:');
    final output = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    try {
      final code = _open(path, output);
      _handle = output.value;
      if (code != 0) throw StateError('SQLite open: $code');
    } finally {
      _free(path.cast());
      _free(output.cast());
    }
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  bool get isOpen => _opened;
  @override
  String get path => ':memory:';

  Pointer<Uint8> _string(String text) {
    final bytes = utf8.encode(text);
    final pointer = _malloc(bytes.length + 1).cast<Uint8>();
    pointer.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
    return pointer;
  }

  String _read(Pointer<Uint8> pointer) {
    var length = 0;
    while (pointer[length] != 0) {
      length++;
    }
    return utf8.decode(pointer.asTypedList(length));
  }

  List<Map<String, Object?>> _run(String sql, List<Object?>? arguments) {
    final text = _string(sql);
    final output = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    Pointer<Void>? statement;
    try {
      final code = _prepare(_handle, text, -1, output, nullptr);
      if (code != 0) throw StateError(_read(_error(_handle)));
      statement = output.value;
      for (var i = 0; i < (arguments?.length ?? 0); i++) {
        final value = arguments![i];
        if (value is Uint8List) {
          final pointer = _malloc(
            value.isEmpty ? 1 : value.length,
          ).cast<Uint8>();
          try {
            pointer.asTypedList(value.length).setAll(0, value);
            _bindBlob(
              statement,
              i + 1,
              pointer,
              value.length,
              Pointer.fromAddress(-1),
            );
          } finally {
            _free(pointer.cast());
          }
        } else if (value is int) {
          _bindInt(statement, i + 1, value);
        } else if (value is double) {
          _bindDouble(statement, i + 1, value);
        } else if (value != null) {
          final pointer = _string(value.toString());
          try {
            _bindText(statement, i + 1, pointer, -1, Pointer.fromAddress(-1));
          } finally {
            _free(pointer.cast());
          }
        }
      }
      final rows = <Map<String, Object?>>[];
      while (true) {
        final code = _step(statement);
        if (code == 101) break;
        if (code != 100) throw StateError(_read(_error(_handle)));
        rows.add({
          for (var c = 0; c < _count(statement); c++)
            _read(_name(statement, c)): switch (_type(statement, c)) {
              1 => _integer(statement, c),
              2 => _double(statement, c),
              3 => _read(_text(statement, c)),
              4 => Uint8List.fromList(
                _blob(statement, c).asTypedList(_bytes(statement, c)),
              ),
              5 => null,
              _ => throw StateError('Testte desteklenmeyen SQLite türü'),
            },
        });
      }
      return rows;
    } finally {
      if (statement != null) _finalize(statement);
      _free(text.cast());
      _free(output.cast());
    }
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    _run(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => _run(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => _run(
    'SELECT ${distinct == true ? 'DISTINCT ' : ''}${columns?.join(', ') ?? '*'} FROM $table'
    '${where == null ? '' : ' WHERE $where'}${groupBy == null ? '' : ' GROUP BY $groupBy'}'
    '${having == null ? '' : ' HAVING $having'}${orderBy == null ? '' : ' ORDER BY $orderBy'}'
    '${limit == null ? '' : ' LIMIT $limit'}${offset == null ? '' : ' OFFSET $offset'}',
    whereArgs,
  );
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    _run(
      'INSERT ${conflictAlgorithm == ConflictAlgorithm.replace ? 'OR REPLACE ' : ''}INTO $table '
      '(${values.keys.join(', ')}) VALUES (${List.filled(values.length, '?').join(', ')})',
      values.values.toList(),
    );
    return _lastId(_handle);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    _run(
      'UPDATE $table SET ${values.keys.map((k) => '$k = ?').join(', ')}${where == null ? '' : ' WHERE $where'}',
      [...values.values, ...?whereArgs],
    );
    return _changes(_handle);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    _run(sql, arguments);
    return _changes(_handle);
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    _run(
      'DELETE FROM $table${where == null ? '' : ' WHERE $where'}',
      whereArgs,
    );
    return _changes(_handle);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    if (_depth > 0) return action(this);
    _depth++;
    try {
      await execute('BEGIN');
      try {
        final result = await action(this);
        await execute('COMMIT');
        return result;
      } catch (_) {
        await execute('ROLLBACK');
        rethrow;
      }
    } finally {
      _depth--;
    }
  }

  @override
  Future<void> close() async {
    _close(_handle);
    _opened = false;
  }
}
