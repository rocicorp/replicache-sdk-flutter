import 'dart:core';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'database_info.dart';

const CHANNEL_NAME = 'replicache.dev';

typedef void SyncHandler(bool syncing);
typedef void SyncProgressHandler(SyncProgress progress);
typedef Future<String> AuthTokenGetter();

class SyncProgress {
  const SyncProgress._new(this.bytesReceived, this.bytesExpected);
  final int bytesReceived;
  final int bytesExpected;
  bool equals(SyncProgress other) {
    return other != null &&
        other.bytesExpected == bytesExpected &&
        other.bytesReceived == bytesReceived;
  }
}

class ScanBound {
  ScanBound(this.id, this.index);
  final ScanId id;
  final int index;
  Map<String, dynamic> _json() {
    var r = {};
    if (this.id != null) {
      r['id'] = this.id._json();
    }
    if (this.index != null) {
      r['index'] = this.index;
    }
    return r;
  }
}

class ScanId {
  ScanId(this.value, this.exclusive);
  final String value;
  final bool exclusive;
  Map<String, dynamic> _json() {
    return {
      'value': value ?? '',
      'exclusive': exclusive ?? false,
    };
  }
}

/// Replicache is a connection to a local Replicache database. There can be multiple
/// connections to the same database.
///
/// Operations are generally async because they go to local storage. However on modern
/// mobile devices this will typically be ~instant, and in most cases no progress UI
/// should be necessary.
///
/// Replicache operations are serialized per-connection, with the sole exception of
/// sync(), which runs concurrently with other operations (and might take awhile, since
/// it attempts to go to the network).
class Replicache implements ReadTransaction {
  static MethodChannel _platform;

  SyncHandler onSync;
  SyncProgressHandler onSyncProgress;
  AuthTokenGetter getClientViewAuth;

  static bool logVerbosely = true;

  /// Gets the last sync progress for this repo.
  SyncProgress get syncProgress => _syncProgress;

  String _name;
  String _remote;
  String _clientViewAuth;
  Future<String> _root;
  Future<dynamic> _opened;
  Timer _timer;
  bool _closed = false;
  bool _reauthenticating = false;
  SyncProgress _syncProgress = SyncProgress._new(0, 0);
  Set<_Subscription> _subscriptions = Set();

  /// Lists information about available local databases.
  static Future<List<DatabaseInfo>> list() async {
    var res = await _invoke('', 'list');
    return List.from(res['databases'].map((d) => DatabaseInfo.fromJson(d)));
  }

  /// Completely delete a local database. Remote replicas in the group aren't affected.
  static Future<void> drop(String name) async {
    await _invoke(name, 'drop');
  }

  static Future<void> _methodChannelHandler(MethodCall call) {
    if (call.method == "log" && logVerbosely) {
      print("Replicache (native): ${call.arguments}");
      return Future.value();
    }
    throw Exception("Unknown method: ${call.method}");
  }

  /// Create or open a local Replicache database with named `name` synchronizing with `remote`.
  /// If `name` is omitted, it defaults to `remote`.
  Replicache(this._remote, {String name = "", String clientViewAuth = ""})
      : _clientViewAuth = clientViewAuth {
    if (_platform == null) {
      _platform = MethodChannel(CHANNEL_NAME);
      _platform.setMethodCallHandler(_methodChannelHandler);
    }

    if (this._remote == "") {
      throw new Exception("remote must be non-empty");
    }
    if (name == "") {
      name = this._remote;
    }
    this._name = name;

    print('Using remote: ' + this._remote);

    _opened = _invoke(_name, 'open');
    _root = _opened.then((_) => _getRoot());
    _root.then((_) {
      this._scheduleSync(0);
    });
  }

  String get name => _name;
  String get remote => _remote;
  String get clientViewAuth => _clientViewAuth;

  /// Puts a single value into the database in its own transaction.
  Future<void> _put(String key, dynamic value) async {
    await _opened;
    return _result(await _checkChange(
        await _invoke(_name, 'put', {'key': key, 'value': value})));
  }

  Future<dynamic> _get(int transactionId, String key) async {
    await _opened;
    return _result(await _invoke(_name, 'get', {
      'transactionId': transactionId,
      'key': key,
    }));
  }

  /// Get a single value from the database.
  Future<dynamic> get(String key) => query((tx) => tx.get(key));

  Future<bool> _has(int transactionId, String key) async {
    await _opened;
    return _result(await _invoke(_name, 'has', {
      'transactionId': transactionId,
      'key': key,
    }));
  }

  /// Determines if a single key is present in the database.
  Future<bool> has(String key) => query((tx) => tx.has(key));

  /// Deletes a single value from the database in its own transaction.
  Future<void> _del(String key) async {
    await _opened;
    return _result(
        await _checkChange(await _invoke(_name, 'del', {'key': key})));
  }

  Future<Iterable<ScanItem>> _scan(
    int transactionId, {
    @required String prefix,
    @required ScanBound start,
    @required int limit,
  }) async {
    var args = {
      'transactionId': transactionId,
      'prefix': prefix,
      'limit': limit,
    };
    if (start != null) {
      args['start'] = start._json();
    }
    List<dynamic> r = await _invoke(_name, 'scan', args);
    await _opened;
    return r.map((e) => ScanItem.fromJson(e));
  }

  /// Gets many values from the database.
  Future<Iterable<ScanItem>> scan({
    String prefix = '',
    ScanBound start,
    int limit = 50,
  }) =>
      query((tx) => tx.scan(prefix: prefix, start: start, limit: limit));

  /// Synchronizes the database with the server. New local transactions that have been executed since the last
  /// sync are sent to the server, and new remote transactions are received and replayed.
  Future<void> sync() async {
    await _opened;
    if (_closed) {
      return;
    }

    if (_timer == null) {
      // Another call stack is already inside sync();
      return;
    }

    _fireOnSync(true);

    Timer progressTimer;

    final checkProgress = () async {
      if (_closed || _reauthenticating) {
        progressTimer.cancel();
        return;
      }
      final result = await _invoke(_name, 'pullProgress', {});
      int r = result['bytesReceived'];
      int e = result['bytesExpected'];
      if (r == 0 && e == 0) {
        return;
      }
      if (e == 0) {
        e = r;
      }
      _fireOnSyncProgress(SyncProgress._new(r, e));
    };

    _syncProgress = const SyncProgress._new(0, 0);

    progressTimer = Timer.periodic(new Duration(milliseconds: 500), (Timer t) {
      checkProgress();
    });

    try {
      _timer.cancel();
      _timer = null;

      for (var i = 0;; i++) {
        Map<String, dynamic> result = await _invoke(_name, 'pull', {
          'remote': _remote,
          'clientViewAuth': _clientViewAuth,
        });
        if (result.containsKey('error') &&
            result['error'].containsKey('badAuth')) {
          _reauthenticating = true;
          print('Auth error: ${result['error']['badAuth']}');
          if (getClientViewAuth == null) {
            print('Auth error: getAuthToken is null');
            break;
          }
          if (i == 2) {
            break;
          }
          print('Refreshing auth token to try again...');
          this._clientViewAuth = await getClientViewAuth();
          _reauthenticating = false;
        } else {
          await _checkChange(result);
          break;
        }
      }
      _scheduleSync(5);
    } catch (e) {
      // We are seeing some consistency errors during sync -- we push commits,
      // then turn around and fetch them and expect to see them, but don't.
      // that is bad, but for now, just retry.
      print('Error syncing: ' + this._remote + ': ' + e.toString());
      _scheduleSync(1);
    } finally {
      progressTimer.cancel();
      await checkProgress();
      this._fireOnSync(false);
    }
  }

  void _scheduleSync(seconds) {
    _timer = new Timer(new Duration(seconds: seconds), sync);
  }

  Future<void> close() async {
    _closed = true;
    for (final subscription in _subscriptions) {
      subscription.streamController.close();
    }
    await _opened;
    await _invoke(_name, 'close');
  }

  Future<String> _getRoot() async {
    await _opened;
    var res = await _invoke(_name, 'getRoot');
    return res['root'];
  }

  dynamic _result(Map<String, dynamic> m) {
    return m == null ? null : m['result'];
  }

  Future<Map<String, dynamic>> _checkChange(Map<String, dynamic> result) async {
    var currentRoot = await _root; // instantaneous except maybe first time
    if (result != null &&
        result['root'] != null &&
        result['root'] != currentRoot) {
      _root = Future.value(result['root']);
      _fireOnChange();
    }
    return result;
  }

  static Future<dynamic> _invoke(String dbName, String rpc,
      [Map<String, dynamic> args = const {}]) async {
    try {
      final r = await _platform.invokeMethod(rpc, [dbName, jsonEncode(args)]);
      return r == '' ? null : jsonDecode(r);
    } catch (e) {
      throw Exception('Error invoking "$rpc": ${e.toString()}');
    }
  }

  void _fireOnSync(bool syncing) {
    if (onSync != null) {
      scheduleMicrotask(() => onSync(syncing));
    }
  }

  void _fireOnSyncProgress(SyncProgress p) {
    if (_syncProgress != null &&
        p.bytesExpected == _syncProgress.bytesExpected &&
        p.bytesReceived == _syncProgress.bytesReceived) {
      return;
    }
    _syncProgress = p;
    if (onSyncProgress != null) {
      scheduleMicrotask(() => onSyncProgress(p));
    }
  }

  void _fireOnChange() async {
    final List<_Subscription> subscriptions =
        _subscriptions.toList(growable: false);
    final results = await query((tx) async {
      final futures =
          subscriptions.map((subscription) => subscription.callback(tx));
      return await Future.wait(futures);
    });
    for (int i = 0; i < subscriptions.length; i++) {
      subscriptions[i].streamController.add(results[i]);
    }
  }

  /// Subcribe to changes to the underlying data. This returns a stream that can
  /// be listened to. Every time the underlying data changes the listener is
  /// invoked. The listener is also invoked once the first time the subscription
  /// is added. There is currently no guarantee that the result of this
  /// subscription changes and it might get called with the same value over and
  /// over.
  Stream<R> subscribe<R>(Future<R> callback(ReadTransaction tx)) async* {
    // One initial call.
    yield await query(callback);

    _Subscription subscription;
    // ignore: close_sinks
    StreamController<R> streamController = StreamController(
      onListen: () => _subscriptions.add(subscription),
      onCancel: () => _subscriptions.remove(subscription),
      onPause: () => _subscriptions.remove(subscription),
      onResume: () => _subscriptions.add(subscription),
    );
    subscription = _Subscription(callback, streamController);

    yield* subscription.streamController.stream;
  }

  /// Query is used for read transactions. It is recommended to use transactions
  /// to ensure you get a consistent view across multiple calls to [get], [has]
  /// and [scan].
  Future<R> query<R>(Future<R> callback(ReadTransaction tx)) async {
    final res = await _invoke(_name, 'openTransaction');
    final txId = res['transactionId'];
    try {
      final tx = _ReadTransactionImpl(this, txId);
      return await callback(tx);
    } finally {
      // No need to await the response.
      _closeTransaction(txId);
    }
  }

  Future<void> _closeTransaction(int txId) async {
    try {
      await _invoke(_name, 'closeTransaction', {'transactionId': txId});
    } catch (ex) {
      print('Failed to close transaction: $ex');
    }
  }
}

class _Subscription<R> {
  final Future<R> Function(ReadTransaction tx) callback;
  final StreamController<R> streamController;
  _Subscription(this.callback, this.streamController);
}

class ScanItem {
  ScanItem.fromJson(Map<String, dynamic> data)
      : key = data['key'],
        value = data['value'];
  String key;

  var value;

  @Deprecated('Use key instead')
  get id => key;
}

/// ReadTransactions are used with [Replicache.query] and allows read operations on the database.
abstract class ReadTransaction {
  /// Get a single value from the database.
  Future<dynamic> get(String key);

  /// Determines if a single key is present in the database.
  Future<bool> has(String key);

  /// Gets many values from the database.
  Future<Iterable<ScanItem>> scan({String prefix, ScanBound start, int limit});
}

class _ReadTransactionImpl implements ReadTransaction {
  final Replicache _db;
  final int _transactionId;

  _ReadTransactionImpl(this._db, this._transactionId);

  Future<dynamic> get(String key) {
    return _db._get(_transactionId, key);
  }

  Future<bool> has(String key) {
    return _db._has(_transactionId, key);
  }

  Future<Iterable<ScanItem>> scan(
      {String prefix = '', ScanBound start, int limit = 50}) {
    return _db._scan(_transactionId,
        prefix: prefix, start: start, limit: limit);
  }
}
