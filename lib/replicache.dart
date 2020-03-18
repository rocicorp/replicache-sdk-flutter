import 'dart:core';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'database_info.dart';

const CHANNEL_NAME = 'replicache.dev';

typedef void ChangeHandler();
typedef void SyncHandler(bool syncing);
typedef void SyncProgressHandler(SyncProgress progress);
typedef Future<String> AuthTokenGetter();

class SyncProgress {
  SyncProgress._new(this.bytesReceived, this.bytesExpected);
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
class Replicache {
  static MethodChannel _platform;

  ChangeHandler onChange;
  SyncHandler onSync;
  SyncProgressHandler onSyncProgress;
  AuthTokenGetter getAuthToken;

  static bool logVerbosely = true;

  /// If true, Replicache only syncs the head of the remote repository, which is
  /// must faster. Currently this disables bidirectional sync though :(.
  bool shallowSync;

  /// @Deprecated('Use shallowSync instead')
  set hackyShallowSync(bool val) {
    shallowSync = true;
  }

  /// @Deprecated('Use shallowSync instead')
  bool get hackyShallowSync => shallowSync;

  /// Gets the last sync progress for this repo.
  SyncProgress get syncProgress => _syncProgress;

  String _name;
  String _remote;
  Future<String> _root;
  Future<dynamic> _opened;
  Timer _timer;
  bool _closed = false;
  String _authToken = "";
  SyncProgress _syncProgress = SyncProgress._new(0, 0);

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
  Replicache(this._remote, {String name = ""}) {
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

    _opened = _invoke(this._name, 'open');
    _root = _opened.then((_) => _getRoot());
    _root.then((_) {
      this._scheduleSync(0);
    });
  }

  String get name => _name;
  String get remote => _remote;

  /// Executes the named function with provided arguments from the current
  /// bundle as an atomic transaction.
  Future<dynamic> exec(String function, [List<dynamic> args = const []]) async {
    await _opened;
    return _result(await _checkChange(
        await _invoke(this._name, 'exec', {'name': function, 'args': args})));
  }

  /// Puts a single value into the database in its own transaction.
  Future<void> put(String id, dynamic value) async {
    await _opened;
    return _result(await _checkChange(
        await _invoke(this._name, 'put', {'id': id, 'value': value})));
  }

  /// Get a single value from the database.
  Future<dynamic> get(String id) async {
    await _opened;
    return _result(await _invoke(this._name, 'get', {'id': id}));
  }

  /// Gets many values from the database.
  Future<Iterable<ScanItem>> scan(
      {prefix: '', ScanBound start, limit: 50}) async {
    var args = {
      'prefix': prefix,
      'limit': limit,
    };
    if (start != null) {
      args['start'] = start._json();
    }
    List<dynamic> r = await _invoke(this._name, 'scan', args);
    await _opened;
    return r.map((e) => ScanItem.fromJson(e));
  }

  /// Synchronizes the database with the server. New local transactions that have been executed since the last
  /// sync are sent to the server, and new remote transactions are received and replayed.
  Future<void> sync() async {
    await _opened;
    if (_closed) {
      return;
    }

    if (_timer == null) {
      // Another call stack is already inside _sync();
      return;
    }

    this._fireOnSync(true);

    final checkProgress = () async {
      final result = await _invoke(this._name, 'syncProgress', {});
      int r = result['bytesReceived'];
      int e = result['bytesExpected'];
      if (r == 0 && e == 0) {
        return;
      }
      if (e == 0) {
        e = r;
      }
      this._fireOnSyncProgress(SyncProgress._new(r, e));
    };

    this._syncProgress = SyncProgress._new(0, 0);

    final progressTimer =
        Timer.periodic(new Duration(milliseconds: 500), (Timer t) {
      checkProgress();
    });

    try {
      _timer.cancel();
      _timer = null;

      for (var i = 0;; i++) {
        Map<String, dynamic> result = await _invoke(this._name, 'requestSync', {
          'remote': this._remote,
          'shallow': this.shallowSync,
          'auth': this._authToken
        });
        if (result.containsKey('error') &&
            result['error'].containsKey('badAuth')) {
          print('Auth error: ${result['error']['badAuth']}');
          if (getAuthToken == null) {
            print('Auth error: getAuthToken is null');
            break;
          }
          if (i == 2) {
            break;
          }
          print('Refreshing auth token to try again...');
          this._authToken = await getAuthToken();
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
    await _opened;
    await _invoke(this.name, 'close');
  }

  Future<String> _getRoot() async {
    await _opened;
    var res = await _invoke(this._name, 'getRoot');
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

  void _fireOnChange() {
    if (onChange != null) {
      scheduleMicrotask(onChange);
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
