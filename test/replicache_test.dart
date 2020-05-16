import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replicache/database_info.dart';
import 'package:replicache/replicache.dart';
import 'package:http/http.dart';

class Replay {
  final String dbName;
  final String method;
  final Uint8List data;
  final String responseBody;

  Replay(this.dbName, this.method, this.data, this.responseBody);

  @override
  operator ==(dynamic other) =>
      other is Replay &&
      other.dbName == dbName &&
      other.method == method &&
      listEquals(other.data, data) &&
      other.responseBody == responseBody;

  @override
  int get hashCode =>
      dbName.hashCode ^ method.hashCode ^ data.hashCode ^ responseBody.hashCode;

  Map<String, dynamic> toJson() => {
        'dbName': dbName,
        'method': method,
        'data': utf8.decode(data),
        'responseBody': responseBody,
      };

  Replay.fromJson(Map<String, dynamic> data)
      : dbName = data['dbName'],
        method = data['method'],
        data = utf8.encode(data['data']),
        responseBody = data['responseBody'];

  bool matches(dbName, method, data) =>
      dbName == this.dbName &&
      method == this.method &&
      listEquals(data, this.data);
}

Future<void> main() async {
  const testServerUrl = 'http://localhost:7002';

  final resp = await get('$testServerUrl/statusz');
  if (resp.statusCode != 200) {
    throw Exception('Test server not running');
  }

  Future<void> addData(WriteTransaction tx, dynamic data) async {
    for (final entry in data.entries) {
      await tx.put(entry.key, entry.value);
    }
  }

  Matcher equalsScanItem(String k, dynamic v) =>
      predicate<ScanItem>((item) => item.key == k && item.value == v);

  Matcher equalsDatabaseInfo(String name) =>
      predicate<DatabaseInfo>((db) => db.name == name);

  Matcher equalsJson(dynamic v) =>
      predicate((o) => o == v || json.encode(o) == json.encode(v));

  Future<void> nextMicrotask() => Future.delayed(Duration());

  TestWidgetsFlutterBinding.ensureInitialized();

  // TODO(arv): Start the test server from here!

  List replays = [];
  String recordPath;

  File fixtureFile(String name) {
    var dir = Directory.current.path;
    if (dir.endsWith('/test')) {
      dir = dir.replaceAll('/test', '');
    }
    return File('$dir/test/$name');
  }

  Future<void> useReplay(String name) async {
    final replaysString = await fixtureFile(name).readAsString();
    replays = json
        .decode(replaysString)
        .toList()
        .map((data) => Replay.fromJson(data))
        .toList();
  }

  const MethodChannel(CHANNEL_NAME)
      .setMockMethodCallHandler((methodCall) async {
    final method = methodCall.method;
    final String dbName = methodCall.arguments[0];
    final Uint8List data = methodCall.arguments[1];

    if (recordPath == null && replays.isNotEmpty) {
      final i = replays.indexWhere((r) => r.matches(dbName, method, data));
      expect(i, isNot(-1));
      final replay = replays[i];
      replays.removeAt(i);
      return replay.responseBody;
    }

    final resp =
        await post('$testServerUrl/?dbname=$dbName&rpc=$method', body: data);
    if (resp.statusCode == 200) {
      if (recordPath != null) {
        replays.add(Replay(dbName, method, data, resp.body));
      }
      return resp.body;
    }
    throw Exception(
        'Test server failed: ${resp.statusCode} ${resp.reasonPhrase}: ${resp.body}');
  });

  setUp(() async {
    HttpOverrides.global = null;
    recordPath = null;
    replays = [];
    final dbs = await Replicache.list();
    for (final DatabaseInfo info in dbs) {
      await Replicache.drop(info.name);
    }
  });

  Replicache rep, rep2;
  tearDown(() async {
    if (rep != null && !rep.closed) {
      await rep.close();
      rep = null;
    }
    if (rep2 != null && !rep2.closed) {
      await rep2.close();
      rep2 = null;
    }

    if (recordPath != null) {
      JsonEncoder encoder = new JsonEncoder.withIndent('  ');
      await fixtureFile(recordPath).writeAsString(encoder.convert(replays));
    }

    recordPath = null;
    replays = [];
  });

  test('list and drop', () async {
    rep = await Replicache.forTesting('def');
    rep2 = await Replicache.forTesting('abc');

    final List<DatabaseInfo> dbs = await Replicache.list();
    expect(
        dbs,
        orderedEquals([
          equalsDatabaseInfo('abc'),
          equalsDatabaseInfo('def'),
        ]));

    {
      await Replicache.drop('abc');
      final List<DatabaseInfo> dbs = await Replicache.list();
      expect(
          dbs,
          orderedEquals([
            equalsDatabaseInfo('def'),
          ]));
    }
  });

  test('get, has, scan on empty db', () async {
    rep = await Replicache.forTesting('def');

    t(ReadTransaction tx) async {
      expect(await tx.get('key'), isNull);
      expect(await tx.has('key'), isFalse);

      final scanItems = await tx.scan();
      expect(scanItems.isEmpty, isTrue);
    }

    await t(rep);
    await rep.query(t);
  });

  test('put, get, has, del inside tx', () async {
    rep = await Replicache.forTesting('def');
    final mut = rep.register('mut', (tx, args) async {
      final key = args['key'];
      final value = args['value'];
      await tx.put(key, value);
      expect(await tx.has(key), isTrue);
      final v = await tx.get(key);
      expect(v, equalsJson(value));

      expect(await tx.del(key), isTrue);
      expect(await tx.has(key), isFalse);
    });

    for (final e in {
      'a': true,
      'b': false,
      'c': null,
      'd': 'string',
      'e': 12,
      'f': {},
      'g': [],
      'h': {'h1': true},
      'i': [0, 1],
    }.entries) {
      await mut({'key': e.key, 'value': e.value});
    }
  });

  test('scan', () async {
    rep = await Replicache.forTesting('def');
    final add = rep.register('add-data', addData);
    await add({
      'a/0': 0,
      'a/1': 1,
      'a/2': 2,
      'a/3': 3,
      'a/4': 4,
      'b/0': 5,
      'b/1': 6,
      'b/2': 7,
      'c/0': 8,
    });

    expect(
        await rep.scan(),
        orderedEquals([
          equalsScanItem('a/0', 0),
          equalsScanItem('a/1', 1),
          equalsScanItem('a/2', 2),
          equalsScanItem('a/3', 3),
          equalsScanItem('a/4', 4),
          equalsScanItem('b/0', 5),
          equalsScanItem('b/1', 6),
          equalsScanItem('b/2', 7),
          equalsScanItem('c/0', 8),
        ]));

    expect(
        await rep.scan(prefix: 'a'),
        orderedEquals([
          equalsScanItem('a/0', 0),
          equalsScanItem('a/1', 1),
          equalsScanItem('a/2', 2),
          equalsScanItem('a/3', 3),
          equalsScanItem('a/4', 4),
        ]));

    expect(
        await rep.scan(prefix: 'b'),
        orderedEquals([
          equalsScanItem('b/0', 5),
          equalsScanItem('b/1', 6),
          equalsScanItem('b/2', 7),
        ]));

    expect(
        await rep.scan(prefix: 'c/'),
        orderedEquals([
          equalsScanItem('c/0', 8),
        ]));

    expect(
        await rep.scan(limit: 3),
        orderedEquals([
          equalsScanItem('a/0', 0),
          equalsScanItem('a/1', 1),
          equalsScanItem('a/2', 2),
        ]));

    expect(
        await rep.scan(start: ScanBound(ScanId('a/1', false), null), limit: 2),
        orderedEquals([
          equalsScanItem('a/1', 1),
          equalsScanItem('a/2', 2),
        ]));

    expect(
        await rep.scan(start: ScanBound(ScanId('a/1', true), null), limit: 2),
        orderedEquals([
          equalsScanItem('a/2', 2),
          equalsScanItem('a/3', 3),
        ]));

    expect(
        await rep.scan(start: ScanBound(ScanId(null, false), 1), limit: 2),
        orderedEquals([
          equalsScanItem('a/1', 1),
          equalsScanItem('a/2', 2),
        ]));
  });

  test('subscribe', () async {
    rep = await Replicache.forTesting('subscribe');
    final repSub = rep.subscribe((tx) async => (await tx.scan(prefix: 'a/')));

    final log = [];
    final sub = repSub.listen((values) {
      for (final scanItem in values) {
        log.add(scanItem);
      }
    });

    expect(log, isEmpty);

    final add = rep.register('add-data', addData);
    await add({'a/0': 0});
    await nextMicrotask();
    expect(
        log,
        orderedEquals([
          equalsScanItem('a/0', 0),
        ]));

    // We might potentially remove this entry if we start checking equality.
    log.clear();
    await add({'a/0': 0});
    await nextMicrotask();
    expect(
        log,
        orderedEquals([
          equalsScanItem('a/0', 0),
        ]));

    log.clear();
    await add({'a/1': 1});
    await nextMicrotask();
    expect(
        log,
        orderedEquals([
          equalsScanItem('a/0', 0),
          equalsScanItem('a/1', 1),
        ]));

    log.clear();
    sub.pause();
    await add({'a/1': 1});
    await nextMicrotask();
    expect(log, isEmpty);

    log.clear();
    sub.resume();
    await add({'a/1': 11});
    await nextMicrotask();
    expect(
        log,
        orderedEquals([
          equalsScanItem('a/0', 0),
          equalsScanItem('a/1', 11),
        ]));

    log.clear();
    sub.cancel();
    await add({'a/1': 11});
    await nextMicrotask();
    expect(log, isEmpty);
  });

  test('subscribe close', () async {
    rep = await Replicache.forTesting('subscribe2');
    final repSub = rep.subscribe((tx) async => (await tx.get('k')));

    final log = [];
    final sub = repSub.listen((value) {
      log.add(value);
    });

    expect(log, isEmpty);

    final add = rep.register('add-data', addData);
    await add({'k': 0});
    await nextMicrotask();
    expect(log, orderedEquals([null, 0]));

    bool done = false;
    sub.onDone(() {
      done = true;
    });

    await rep.close();
    expect(done, isTrue);
    sub.cancel();
  });

  test('name', () async {
    final repA = await Replicache.forTesting('name', name: 'a');
    final repB = await Replicache.forTesting('name', name: 'b');

    final addA = repA.register('add-data', addData);
    final addB = repB.register('add-data', addData);

    await addA({'key': 'A'});
    await addB({'key': 'B'});

    expect(await repA.get('key'), 'A');
    expect(await repB.get('key'), 'B');

    await repA.close();
    await repB.close();
  });

  test('register with error', () async {
    rep = await Replicache.forTesting('regerr');

    final doErr = rep.register('err', (tx, args) async {
      throw args;
    });

    try {
      await doErr(42);
      fail('Should have thrown');
    } catch (ex) {
      expect(ex, 42);
    }
  });

  test('subscribe with error', () async {
    rep = await Replicache.forTesting('suberr');

    final add = rep.register('add-data', addData);

    final repSub = rep.subscribe((tx) async {
      final v = await tx.get('k');
      if (v != null) {
        throw v;
      }
    });
    await nextMicrotask();

    int gottenValue = 0;
    final sub = repSub.listen((x) {
      gottenValue++;
    });

    var error;
    sub.onError((e) {
      error = e;
    });

    expect(error, isNull);
    expect(gottenValue, 0);

    await add({'k': 'throw'});
    expect(gottenValue, 1);
    await nextMicrotask();
    expect(error, 'throw');

    await add({'k': null});

    await nextMicrotask();
    expect(gottenValue, 2);

    await sub.cancel();
  });

  test('conflicting commits', () async {
    // This test does not use pure functions in the mutations. This is of course
    // not a good practice but it makes testing easier.
    final ac = Completer();
    final bc = Completer();

    rep = await Replicache.forTesting('conflict');
    final mutA = rep.register('mutA', (tx, v) async {
      await tx.put('k', v);
      await ac.future;
    });
    final mutB = rep.register('mutB', (tx, v) async {
      await tx.put('k', v);
      await bc.future;
    });

    // Start A and B at the same commit.
    final resAFuture = mutA('a');
    final resBFuture = mutB('b');

    // Finish A.
    ac.complete();
    await resAFuture;
    expect(await rep.get('k'), 'a');

    // Finish B. B will conflict and retry!
    bc.complete();
    await resBFuture;
    expect(await rep.get('k'), 'b');
  });

  test('sync', () async {
    // recordPath = './sync_replay.json';
    await useReplay('./sync_replay.json');

    rep = await Replicache.forTesting(
      'http://localhost:7001/pull',
      name: 'sync',
      batchUrl: 'https://replicache-sample-todo.now.sh/serve/replicache-batch',
      dataLayerAuth: '1',
      diffServerAuth: 'sandbox',
    );

    Completer c = Completer();
    c.complete();

    int count = 0;

    final createTodo = rep.register('createTodo', (tx, args) async {
      count++;
      await tx.put('/todo/${args['id']}', args);
      await c.future;
    });

    final deleteTodo = rep.register('deleteTodo', (tx, args) async {
      count++;
      await tx.del('/todo/${args['id']}');
    });

    final syncHead = await (rep as dynamic).beginSync();

    final id1 = 14323534;
    final id2 = 22354345;
    final id3 = 34645673;

    await createTodo({
      'id': id1,
      'listId': 1,
      'text': 'Test',
      'complete': false,
      'order': 10000,
    });
    expect(count, 1);
    expect((await rep.get('/todo/$id1'))['text'], 'Test');

    await createTodo({
      'id': id2,
      'listId': 1,
      'text': 'Test 2',
      'complete': false,
      'order': 20000,
    });
    expect(count, 2);
    expect((await rep.get('/todo/$id2'))['text'], 'Test 2');

    c = Completer();

    final f = (rep as dynamic).maybeEndSync(syncHead);

    final f2 = createTodo({
      'id': id3,
      'listId': 1,
      'text': 'Test 3',
      'complete': false,
      'order': 30000,
    });

    c.complete();

    await f2;
    expect((await rep.get('/todo/$id3'))['text'], 'Test 3');

    await f;
    expect(count, 6);

    {
      final syncHead = await (rep as dynamic).beginSync();
      await (rep as dynamic).maybeEndSync(syncHead);
      expect(count, 6);
    }

    {
      final syncHead = await (rep as dynamic).beginSync();
      await (rep as dynamic).maybeEndSync(syncHead);
      expect(count, 6);
    }

    await deleteTodo({'id': id1});
    await deleteTodo({'id': id2});
    await deleteTodo({'id': id3});

    final f3 = rep.sync();
    final f4 = rep.sync();
    await f3;
    await f4;
  });
}
