import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replicache/database_info.dart';
import 'package:replicache/replicache.dart';
import 'package:http/http.dart';

Future<void> main() async {
  const testServerUrl = 'http://localhost:7002';

  final resp = await get('$testServerUrl/statusz');
  if (resp.statusCode != 200) {
    throw Exception('Test server not running');
  }

  Future<void> addData(WriteTransaction tx, Map<String, dynamic> data) async {
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

  const MethodChannel(CHANNEL_NAME)
      .setMockMethodCallHandler((methodCall) async {
    final method = methodCall.method;
    final String dbName = methodCall.arguments[0];
    final Uint8List data = methodCall.arguments[1];
    final resp =
        await post('$testServerUrl/?dbname=$dbName&rpc=$method', body: data);
    if (resp.statusCode == 200) {
      return resp.body;
    }
    throw Exception(
        'Test server failed: ${resp.statusCode} ${resp.reasonPhrase}: ${resp.body}');
  });

  setUp(() async {
    HttpOverrides.global = null;
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
  });

  test('list and drop', () async {
    rep = Replicache('def');
    rep2 = Replicache('abc');

    // There is no way to wait for the implicit open in the constructor.
    await Future.delayed(Duration(seconds: 1));

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
    rep = Replicache('def');

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
    rep = Replicache('def');
    final mut = rep.register('mut', (tx, Map<String, dynamic> args) async {
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
    rep = Replicache('def');
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
    rep = Replicache('subscribe');
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
    rep = Replicache('subscribe2');
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
    final repA = Replicache('name', name: 'a');
    final repB = Replicache('name', name: 'b');

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
    rep = Replicache('regerr');

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
    rep = Replicache('suberr');

    final add = rep.register('add-data', addData);

    final repSub = rep.subscribe((tx) async {
      final v = await tx.get('k');
      print('v: $v');
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

    rep = Replicache('conflict');
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
}
