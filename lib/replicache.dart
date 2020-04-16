import 'dart:core';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'database_info.dart';

const CHANNEL_NAME = 'replicache.dev';

typedef void ChangeHandler();
typedef void PullHandler(bool pulling);
typedef void PullProgressHandler(PullProgress progress);
typedef Future<String> AuthTokenGetter();

class PullProgress {
  const PullProgress._new(this.bytesReceived, this.bytesExpected);
  final int bytesReceived;
  final int bytesExpected;
  bool equals(PullProgress other) {
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
/// pull(), which runs concurrently with other operations (and might take awhile, since
/// it attempts to go to the network).
class Replicache implements ReadTransaction {
  static MethodChannel _platform;

  ChangeHandler onChange;
  PullHandler onPull;
  PullProgressHandler onPullProgress;
  AuthTokenGetter getClientViewAuth;

  static bool logVerbosely = true;

  /// Gets the last pull progress for this repo.
  PullProgress get pullProgress => _pullProgress;

  String _name;
  String _remote;
  String _clientViewAuth;
  Future<String> _root;
  Future<dynamic> _opened;
  Timer _timer;
  bool _closed = false;
  bool _reauthenticating = false;
  PullProgress _pullProgress = PullProgress._new(0, 0);

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
      this._schedulePull(0);
    });
  }

  String get name => _name;
  String get remote => _remote;
  String get clientViewAuth => _clientViewAuth;

  /// Puts a single value into the database in its own transaction.
  Future<void> _put(String id, dynamic value) async {
    await _opened;
    return _result(await _checkChange(
        await _invoke(_name, 'put', {'id': id, 'value': value})));
  }

  Future<dynamic> _get(int transactionId, String id) async {
    await _opened;
    return _result(await _invoke(_name, 'get', {
      'transactionId': transactionId,
      'id': id,
    }));
  }

  /// Get a single value from the database.
  Future<dynamic> get(String id) => query((tx) => tx.get(id));

  Future<bool> _has(int transactionId, String id) async {
    await _opened;
    return _result(await _invoke(_name, 'has', {
      'transactionId': transactionId,
      'id': id,
    }));
  }

  /// Determines if a single key is present in the database.
  Future<bool> has(String id) => query((tx) => tx.has(id));

  /// Deletes a single value from the database in its own transaction.
  Future<void> _del(String id) async {
    await _opened;
    return _result(await _checkChange(await _invoke(_name, 'del', {'id': id})));
  }

  Future<Iterable<ScanItem>> _scan(
    int transactionId, {
    @required prefix,
    @required ScanBound start,
    @required limit,
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
    prefix,
    ScanBound start,
    limit,
  }) =>
      query((tx) => tx.scan(prefix: prefix, start: start, limit: limit));

  /// Synchronizes the database with the server. New local transactions that have been executed since the last
  /// pull are sent to the server, and new remote transactions are received and replayed.
  Future<void> pull() async {
    await _opened;
    if (_closed) {
      return;
    }

    if (_timer == null) {
      // Another call stack is already inside pull();
      return;
    }

    this._fireOnPull(true);

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
      this._fireOnPullProgress(PullProgress._new(r, e));
    };

    this._pullProgress = const PullProgress._new(0, 0);

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
      _schedulePull(5);
    } catch (e) {
      // We are seeing some consistency errors during pull -- we push commits,
      // then turn around and fetch them and expect to see them, but don't.
      // that is bad, but for now, just retry.
      print('Error pulling: ' + this._remote + ': ' + e.toString());
      _schedulePull(1);
    } finally {
      progressTimer.cancel();
      await checkProgress();
      this._fireOnPull(false);
    }
  }

  void _schedulePull(seconds) {
    _timer = new Timer(new Duration(seconds: seconds), pull);
  }

  Future<void> close() async {
    _closed = true;
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
      throw new Exception('Error invoking "' + rpc + '": ' + e.toString());
    }
  }

  void _fireOnPull(bool pulling) {
    if (onPull != null) {
      scheduleMicrotask(() => onPull(pulling));
    }
  }

  void _fireOnPullProgress(PullProgress p) {
    if (_pullProgress != null &&
        p.bytesExpected == _pullProgress.bytesExpected &&
        p.bytesReceived == _pullProgress.bytesReceived) {
      return;
    }
    _pullProgress = p;
    if (onPullProgress != null) {
      scheduleMicrotask(() => onPullProgress(p));
    }
  }

  void _fireOnChange() {
    if (onChange != null) {
      scheduleMicrotask(onChange);
    }
  }

  Future<R> query<R>(Future<R> callback(ReadTransaction tx)) async {
    final res = await _invoke(_name, 'beginTransaction');
    final txId = res['transactionId'];
    bool ok = false;
    try {
      final tx = ReadTransactionImpl(this, txId);
      final result = await callback(tx);
      ok = true;
      return result;
    } finally {
      await _invoke(_name, ok ? 'commitTransaction' : 'closeTransaction',
          {'transactionId': txId});
    }
  }
}

class ScanItem {
  ScanItem.fromJson(Map<String, dynamic> data)
      : id = data['id'],
        value = data['value'];
  String id;
  var value;
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

class ReadTransactionImpl implements ReadTransaction {
  final Replicache _db;
  final int _transactionId;

  ReadTransactionImpl(this._db, this._transactionId);

  Future<dynamic> get(String key) {
    return _db._get(_transactionId, key);
  }

  Future<bool> has(String key) {
    return _db._has(_transactionId, key);
  }

  Future<Iterable<ScanItem>> scan({prefix: '', ScanBound start, limit: 50}) {
    return _db._scan(_transactionId,
        prefix: prefix, start: start, limit: limit);
  }
}
