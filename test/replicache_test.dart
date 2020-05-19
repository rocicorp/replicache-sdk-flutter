import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:replicache/database_info.dart';
import 'package:replicache/replicache.dart';
import 'package:replicache/repm_invoker.dart';
import 'package:http/http.dart';

enum TestMode { Replay, Record, Live }

class Replay {
  final String dbName;
  final String method;
  final dynamic args;
  final dynamic result;
  String jsonArgs;

  Replay(this.dbName, this.method, this.args, this.result) {
    jsonArgs = json.encode(this.args);
  }

  Map<String, dynamic> toJson() => {
        'dbName': dbName,
        'method': method,
        'args': args,
        'result': result,
      };

  factory Replay.fromJson(Map<String, dynamic> data) =>
      Replay(data['dbName'], data['method'], data['args'], data['result']);

  bool matches(String dbName, String method, dynamic args) =>
      method == this.method &&
      json.encode(args) == jsonArgs &&
      dbName == this.dbName;
}

// A ref looks like this: e99uif9c7bpavajrt666es1ki52dv239
RegExp refRegExp = new RegExp(r'^[0-9a-v]{32}$');

Map<String, String> refsMap;

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

  const String emptyHash = "00000000000000000000000000000000";

  Future<void> nextMicrotask() => Future.delayed(Duration());

  TestWidgetsFlutterBinding.ensureInitialized();

  // TODO(arv): Start the test server from here!

  List replays;
  File fixtureFile;

  Future<dynamic> Function(String dbName, String rpc, [dynamic args]) invoke;

  RepmHttpInvoker httpInvoker = RepmHttpInvoker('http://localhost:7002');
  final httpInvoke = httpInvoker.invoke;

  Future<dynamic> recordInvoke(String dbName, String rpc,
      [dynamic args]) async {
    expect(fixtureFile, isNotNull);
    final result = await httpInvoke(dbName, rpc, args);
    replays.add(Replay(dbName, rpc, args, result));
    return result;
  }

  Future<dynamic> replayInvoke(String dbName, String rpc,
      [dynamic args]) async {
    expect(fixtureFile, isNotNull);
    assert(replays != null, 'No replays found');

    final i = replays.indexWhere((r) => r.matches(dbName, rpc, args));
    expect(i, isNot(-1),
        reason:
            'Cannot find recorded response for request: ($dbName, $rpc, ${json.encode(args)}) - perhaps you need to update the test fixture file');

    final replay = replays[i];
    replays.removeAt(i);
    // A microtask is not sufficient to emulate the RPC. We need to go to the
    // event loop.
    await Future.delayed(Duration.zero);
    return replay.result;
  }

  TestMode testMode;

  switch (Platform.environment['TEST_MODE'] ?? 'live') {
    case 'replay':
      testMode = TestMode.Replay;
      invoke = replayInvoke;
      break;
    case 'live':
      testMode = TestMode.Live;
      invoke = httpInvoke;
      break;
    case 'record':
      testMode = TestMode.Record;
      invoke = recordInvoke;
      break;
    default:
      fail('Unexpected TEST_MODE');
  }

  Future<void> useReplay(String name) async {
    Future<File> ff() {
      var dir = Directory.current.path;
      if (dir.endsWith('/test')) {
        dir = dir.replaceAll('/test', '');
      }
      return File('$dir/test/fixtures/$name.json').create(recursive: true);
    }

    switch (testMode) {
      case TestMode.Replay:
        fixtureFile = await ff();
        final replaysString = await (fixtureFile).readAsString();
        if (replaysString.isEmpty) {
          replays = null;
        } else {
          replays = json
              .decode(replaysString)
              .toList()
              .map((data) => Replay.fromJson(data))
              .toList();
        }
        break;
      case TestMode.Record:
        fixtureFile = await ff();
        replays = [];
        break;
      case TestMode.Live:
        break;
    }
  }

  Future<Replicache> replicacheForTesting(
    String name, {
    String diffServerUrl = 'https://serve.replicache.dev/pull',
    String dataLayerAuth = '',
    String diffServerAuth = '',
    String batchUrl = '',
  }) =>
      Replicache.forTesting(
        diffServerUrl: diffServerUrl,
        name: name,
        dataLayerAuth: dataLayerAuth,
        diffServerAuth: diffServerAuth,
        batchUrl: batchUrl,
        repmInvoke: invoke,
      );

  setUp(() async {
    HttpOverrides.global = null;
    refsMap = Map();
    if (testMode != TestMode.Replay) {
      final dbs = await Replicache.list(repmInvoke: httpInvoke);
      for (final DatabaseInfo info in dbs) {
        await Replicache.drop(info.name, repmInvoke: httpInvoke);
      }
    }
  });

  Replicache rep, rep2;
  tearDown(() async {
    // _closeTransaction is async but we do not wait for it which can lead to
    // us closing the db before the tx is done. For the tests we do not want
    // these errors.
    await Future.delayed(Duration(milliseconds: 300));

    if (rep != null && !rep.closed) {
      await rep.close();
      rep = null;
    }
    if (rep2 != null && !rep2.closed) {
      await rep2.close();
      rep2 = null;
    }

    if (testMode == TestMode.Record) {
      JsonEncoder encoder = new JsonEncoder.withIndent('  ');
      await fixtureFile.writeAsString(encoder.convert(replays));
    }

    replays = null;
    fixtureFile = null;
  });

  test('list and drop', () async {
    await useReplay('list and drop');

    rep = await replicacheForTesting('def');
    rep2 = await replicacheForTesting('abc');

    final List<DatabaseInfo> dbs = await Replicache.list(repmInvoke: invoke);
    expect(
        dbs,
        orderedEquals([
          equalsDatabaseInfo('abc'),
          equalsDatabaseInfo('def'),
        ]));

    {
      await Replicache.drop('abc', repmInvoke: invoke);
      final List<DatabaseInfo> dbs = await Replicache.list(repmInvoke: invoke);
      expect(
          dbs,
          orderedEquals([
            equalsDatabaseInfo('def'),
          ]));
    }
  });

  test('get, has, scan on empty db', () async {
    await useReplay('get, has, scan on empty db');

    rep = await replicacheForTesting('test2');

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
    await useReplay('put, get, has, del inside tx');

    rep = await replicacheForTesting('test3');
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
    await useReplay('scan');

    rep = await replicacheForTesting('test4');
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
    await useReplay('subscribe');

    rep = await replicacheForTesting('subscribe');
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
    await useReplay('subscribe close');

    rep = await replicacheForTesting('subscribe-close');
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
    await useReplay('name');

    final repA = await replicacheForTesting('a');
    final repB = await replicacheForTesting('b');

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
    await useReplay('register with error');

    rep = await replicacheForTesting('regerr');

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
    await useReplay('subscribe with error');

    rep = await replicacheForTesting('suberr');

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
    await useReplay('conflicting commits');

    // This test does not use pure functions in the mutations. This is of course
    // not a good practice but it makes testing easier.
    final ac = Completer();
    final bc = Completer();

    rep = await replicacheForTesting('conflict');
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
    await useReplay('sync');

    rep = await replicacheForTesting(
      'sync',
      batchUrl: 'https://replicache-sample-todo.now.sh/serve/replicache-batch',
      dataLayerAuth: '1',
      diffServerAuth: '1',
    );

    Completer c = Completer();
    c.complete();

    int createCount = 0;
    int deleteCount = 0;
    String syncHead;

    final createTodo = rep.register('createTodo', (tx, args) async {
      createCount++;
      await tx.put('/todo/${args['id']}', args);
    });

    final deleteTodo = rep.register('deleteTodo', (tx, args) async {
      deleteCount++;
      await tx.del('/todo/${args['id']}');
    });

    final id1 = 14323534;
    final id2 = 22354345;

    await deleteTodo({'id': id1});
    await deleteTodo({'id': id2});

    expect(deleteCount, 2);

    await rep.sync();
    expect(deleteCount, 2);

    syncHead = await (rep as dynamic).beginSync();
    expect(syncHead, emptyHash);
    expect(deleteCount, 2);

    await createTodo({
      'id': id1,
      'listId': 1,
      'text': 'Test',
      'complete': false,
      'order': 10000,
    });
    expect(createCount, 1);
    expect((await rep.get('/todo/$id1'))['text'], 'Test');

    syncHead = await (rep as dynamic).beginSync();
    expect(syncHead, isNot(emptyHash));

    await createTodo({
      'id': id2,
      'listId': 1,
      'text': 'Test 2',
      'complete': false,
      'order': 20000,
    });
    expect(createCount, 2);
    expect((await rep.get('/todo/$id2'))['text'], 'Test 2');

    await (rep as dynamic).maybeEndSync(syncHead);

    expect(createCount, 3);

    // Clean up
    await deleteTodo({'id': id1});
    await deleteTodo({'id': id2});

    expect(deleteCount, 4);
    expect(createCount, 3);

    await rep.sync();

    expect(deleteCount, 4);
    expect(createCount, 3);
  });
}
