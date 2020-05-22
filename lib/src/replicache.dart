import 'dart:core';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'repm_invoker.dart';
import 'database_info.dart';
import 'log.dart';
import 'scan_item.dart';
import 'scan_bound.dart';
import 'transactions.dart';

typedef void SyncHandler(bool syncing);
typedef Future<String> AuthTokenGetter();

typedef Future<Return> Mutator<Return, Args>(Args args);
typedef Future<Return> MutatorImpl<Return, Args>(
    WriteTransaction tx, Args args);

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
  SyncHandler onSync;
  AuthTokenGetter getDataLayerAuth;

  final Map<String, MutatorImpl> _mutatorRegistry = {};
  final String _name;
  final String _diffServerUrl;
  String _dataLayerAuth;
  String _diffServerAuth;
  final String _batchUrl;
  Future<String> _root;
  Future<dynamic> _opened;
  Timer _timer;
  Duration _syncInterval;
  bool _closed = false;
  Set<_Subscription> _subscriptions = Set();
  Future<void> _syncFuture;
  RepmInvoke _repmInvoke;
  bool _online = true;

  /// Lists information about available local databases.
  static Future<List<DatabaseInfo>> list({RepmInvoke repmInvoke}) async {
    var res = await _staticInvoke('', 'list', repmInvoke: repmInvoke);
    return List.from(res['databases'].map((d) => DatabaseInfo.fromJson(d)));
  }

  /// Completely delete a local database. Remote replicas in the group aren't affected.

  static Future<void> drop(String name, {RepmInvoke repmInvoke}) async {
    await _staticInvoke(name, 'drop', repmInvoke: repmInvoke);
  }

  /// Sets the verbosity level Replicache logs at. By default,
  /// Replicache logs at [LogLevel.info].
  static set logLevel(LogLevel level) {
    _staticInvoke(
      '',
      'setLogLevel',
      args: {
        LogLevel.debug: 'debug',
        LogLevel.info: 'info',
        LogLevel.error: 'error',
      }[level],
    );
    globalLogLevel = level;
  }

  /// Gets the current verbosity level Replicache logs at.
  static LogLevel get logLevel {
    return globalLogLevel;
  }

  bool get online {
    return _online;
  }

  /// Create or open a local Replicache database with named `name` synchronizing
  /// with `remote`. If `name` is omitted, it defaults to `remote`. `repmInvoke`
  /// is used to talk to the native Replicache module. It can be provided to
  /// allow mocking out the underlying implementation.
  factory Replicache({
    @required String diffServerUrl,
    String name = '',
    String dataLayerAuth = '',
    String diffServerAuth = '',
    String batchUrl = '',
    RepmInvoke repmInvoke,
  }) {
    final rep = Replicache._new(
      diffServerUrl: diffServerUrl,
      name: name,
      dataLayerAuth: dataLayerAuth,
      diffServerAuth: diffServerAuth,
      batchUrl: batchUrl,
      syncInterval: Duration(minutes: 1),
      repmInvoke: repmInvoke,
    );
    rep._open();
    return rep;
  }

  Replicache._new({
    @required String diffServerUrl,
    String name = '',
    String dataLayerAuth = '',
    String diffServerAuth = '',
    String batchUrl = '',
    Duration syncInterval,
    RepmInvoke repmInvoke,
  })  : _diffServerUrl = diffServerUrl,
        _dataLayerAuth = dataLayerAuth,
        _diffServerAuth = diffServerAuth,
        _batchUrl = batchUrl,
        // TODO(arv): Probably does not make much sense to have name default to
        // the diffServerUrl. Make it a required param?
        _name = name.isEmpty ? diffServerUrl : name,
        _syncInterval = syncInterval,
        _repmInvoke = repmInvoke {
    if (_diffServerUrl.isEmpty) {
      throw Exception('remote must be non-empty');
    }
    _open();
  }

  /// Sets the level of verbosity Replicache should log at.
  static setLogLevel(LogLevel level) {
    globalLogLevel = level;
    _staticInvoke('', 'setLogLevel',
        args: {
          LogLevel.debug: 'debug',
          LogLevel.info: 'info',
          LogLevel.error: 'error',
        }[level]);
  }

  Future<void> _open() async {
    _opened = _staticInvoke(_name, 'open', repmInvoke: _repmInvoke);
    _root = _getRoot();
    await _root;
    if (_syncInterval != null) {
      await sync();
    }
  }

  String get name => _name;
  String get remote => _diffServerUrl;
  String get dataLayerAuth => _dataLayerAuth;

  Duration get syncInterval => _syncInterval;

  /// The duration between each [sync]. Set this to [null] to prevent syncing in
  /// the background.
  set syncInterval(Duration duration) {
    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
    _syncInterval = duration;
    _scheduleSync();
  }

  bool get closed => _closed;

  /// Get a single value from the database.
  Future<dynamic> get(String key) => query((tx) => tx.get(key));

  /// Determines if a single key is present in the database.
  Future<bool> has(String key) => query((tx) => tx.has(key));

  /// Gets many values from the database.
  Future<Iterable<ScanItem>> scan({
    String prefix = '',
    ScanBound start,
    int limit = 50,
  }) =>
      query((tx) => tx.scan(prefix: prefix, start: start, limit: limit));

  Future<void> _sync() async {
    try {
      final syncHead = await _beginSync();
      if (syncHead != '00000000000000000000000000000000') {
        await _maybeEndSync(syncHead);
      }
      _online = true;
    } catch (e) {
      print('Error: $e');
      _online = false;
      rethrow;
    }
  }

  Future<String> _beginSync() async {
    final beginSyncResult = await _invoke('beginSync', {
      'batchPushURL': _batchUrl,
      'diffServerURL': _diffServerUrl,
      'dataLayerAuth': _dataLayerAuth,
      'diffServerAuth': _diffServerAuth,
    });

    final syncInfo = beginSyncResult['syncInfo'];

    bool reauth = false;

    void checkStatus(Map<String, dynamic> data, String serverName) {
      final httpStatusCode = data['httpStatusCode'];
      if (data['errorMessage'] != '') {
        error(
            'Got error response from $serverName server: $httpStatusCode: ${data['errorMessage']}');
      }
      if (httpStatusCode == HttpStatus.unauthorized) {
        reauth = true;
      }
    }

    final batchPushInfo = syncInfo['batchPushInfo'];
    if (batchPushInfo != null) {
      checkStatus(batchPushInfo, 'batch');
      final mutationInfos = batchPushInfo['batchPushResponse']['mutationInfos'];
      if (mutationInfos != null) {
        for (final mutationInfo in mutationInfos) {
          error(
              'MutationInfo: ID: ${mutationInfo['id']}, Error: ${mutationInfo['error']}');
        }
      }
    }

    checkStatus(syncInfo['clientViewInfo'], 'client view');

    if (reauth && getDataLayerAuth != null) {
      _dataLayerAuth = await getDataLayerAuth();
      if (_dataLayerAuth != null) {
        // Try again now instead of waiting for another 5 seconds.
        return await _beginSync();
      }
    }

    return beginSyncResult['syncHead'];
  }

  Future<void> _maybeEndSync(String syncHead) async {
    if (_closed) {
      return;
    }
    final res = await _invoke('maybeEndSync', {'syncHead': syncHead});
    final replayMutations = res['replayMutations'];
    if (replayMutations == null || replayMutations.isEmpty) {
      // All done.
      await _checkChange(syncHead);
      return;
    }

    // Replay.
    for (final Map<String, dynamic> mutation in replayMutations) {
      syncHead = await _replay(
        syncHead,
        mutation['original'],
        mutation['name'],
        mutation['args'],
      );
    }

    await _maybeEndSync(syncHead);
  }

  Future<String> _replay<R, A>(
    String basis,
    String original,
    String name,
    A args,
  ) async {
    final mutatorImpl = _mutatorRegistry[name];
    final res = await _mutate(
      name,
      mutatorImpl,
      args,
      invokeArgs: {
        'rebaseOpts': {
          'basis': basis,
          'original': original,
        }
      },
      shouldCheckChange: false,
    );
    return res.ref;
  }

  /// Synchronizes this cache with the server. New local mutations are sent to
  /// the server, and the latest server state is applied to the cache. Any local
  /// mutations not included in the new server state are replayed. See the
  /// Replicache design document for more information on sync:
  /// https://github.com/rocicorp/replicache/blob/master/design.md
  Future<void> sync() async {
    if (_closed) {
      return;
    }

    if (_syncFuture != null) {
      await _syncFuture;
      return;
    }

    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
    _fireOnSync(true);

    try {
      _syncFuture = _sync();
      await _syncFuture;
    } finally {
      _syncFuture = null;
      this._fireOnSync(false);
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    if (_syncInterval != null) {
      _timer = Timer(_syncInterval, sync);
    }
  }

  Future<void> close() async {
    _closed = true;
    final f = _invoke('close');

    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
    for (final subscription in _subscriptions) {
      if (!subscription.streamController.isClosed) {
        subscription.streamController.close();
      }
    }
    _subscriptions.clear();

    await f;
  }

  Future<String> _getRoot() async {
    if (_closed) {
      return null;
    }
    final res = await _invoke('getRoot');
    return res['root'];
  }

  Future<void> _checkChange(String root) async {
    var currentRoot = await _root; // instantaneous except maybe first time
    if (root != null && root != currentRoot) {
      _root = Future.value(root);
      await _fireOnChange();
    }
  }

  Future<dynamic> _invoke(String rpc, [dynamic args = const {}]) async {
    await _opened;
    return await _staticInvoke(_name, rpc, args: args, repmInvoke: _repmInvoke);
  }

  static Future<dynamic> _staticInvoke(String dbName, String rpc,
      {dynamic args = const {}, RepmInvoke repmInvoke}) {
    if (repmInvoke == null) {
      final invoker = RepmMethodChannelInvoker();
      repmInvoke = invoker.invoke;
    }

    return repmInvoke(dbName, rpc, args);
  }

  void _fireOnSync(bool syncing) {
    if (onSync != null) {
      scheduleMicrotask(() => onSync(syncing));
    }
  }

  Future<void> _fireOnChange() async {
    final List<_Subscription> subscriptions = _subscriptions
        .where((s) => !s.streamController.isPaused)
        .toList(growable: false);
    final results = await query((tx) async {
      final futures = subscriptions.map((s) async {
        // Tag the result so we can deal with success vs error below.
        try {
          return _SubscriptionSuccess(await s.callback(tx));
        } catch (ex) {
          return _SubscriptionError(ex);
        }
      });
      return await Future.wait(futures);
    });
    for (int i = 0; i < subscriptions.length; i++) {
      final result = results[i];
      if (result is _SubscriptionSuccess) {
        subscriptions[i].streamController.add(result.value);
      } else {
        subscriptions[i]
            .streamController
            .addError((result as _SubscriptionError).error);
      }
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
      onListen: () {
        _subscriptions.add(subscription);
      },
      onCancel: () {
        _subscriptions.remove(subscription);
      },
    );
    subscription = _Subscription(callback, streamController);
    yield* subscription.streamController.stream;
  }

  /// Query is used for read transactions. It is recommended to use transactions
  /// to ensure you get a consistent view across multiple calls to [get], [has]
  /// and [scan].
  Future<R> query<R>(Future<R> callback(ReadTransaction tx)) async {
    final res = await _invoke('openTransaction');
    final txId = res['transactionId'];
    try {
      final tx = ReadTransactionImpl(this._invoke, txId);
      return await callback(tx);
    } finally {
      // No need to await the response.
      _closeTransaction(txId);
    }
  }

  /// Registers a *mutator*, which is used to make changes to the data.
  ///
  /// ## Replays
  ///
  /// Mutators run once when they are initially invoked, but they might also be
  /// *replayed* multiple times during sync. As such mutators should not modify
  /// application state directly. Also, it is important that the set of
  /// registered mutator names only grows over time. If Replicache syncs and
  /// needed mutator is not registered, it will substitute a no-op mutator, but
  /// this might be a poor user experience.
  ///
  /// ## Server application
  ///
  /// During sync, a description of each mutation is sent to the server's [batch
  /// endpoint](https://github.com/rocicorp/replicache/blob/master/README.md#step-5-upstream-sync)
  /// where it is applied. Once the mutation has been applied successfully, as
  /// indicated by the [client
  /// view](https://github.com/rocicorp/replicache/blob/master/README.md#step-2-downstream-sync)'s
  /// `lastMutationId` field, the local version of the mutation is removed. See
  /// the [design
  /// doc](https://github.com/rocicorp/replicache/blob/master/design.md) for
  /// additional details on the sync protocol.
  ///
  /// ## Transactionality
  ///
  /// Mutators are atomic: all their changes are applied together, or none are.
  /// Throwing an exception aborts the transaction. Otherwise, it is committed.
  /// As with [query] and [subscribe] all reads will see a consistent view of
  /// the cache while they run.
  Mutator<Return, Args> register<Return, Args>(
    String name,
    MutatorImpl<Return, Args> mutatorImpl,
  ) {
    _mutatorRegistry[name] = mutatorImpl as MutatorImpl;
    return (Args args) async => (await _mutate(
          name,
          mutatorImpl,
          args,
          shouldCheckChange: true,
        ))
            .result;
  }

  Future<_MutateResult<R>> _mutate<R, A>(
    String name,
    MutatorImpl<R, A> mutatorImpl,
    A args, {
    Map<String, dynamic> invokeArgs,
    @required bool shouldCheckChange,
  }) async {
    final actualInvokeArgs = {'args': args, 'name': name};
    if (invokeArgs != null) {
      actualInvokeArgs.addAll(invokeArgs);
    }

    final res = await _invoke('openTransaction', actualInvokeArgs);
    final txId = res['transactionId'];
    R rv;
    try {
      final tx = newWriteTransaction(this._invoke, txId);
      rv = await Function.apply(mutatorImpl, [tx, args]);
    } catch (ex) {
      // No need to await the response.
      _closeTransaction(txId);
      rethrow;
    }
    final commitRes =
        await _invoke('commitTransaction', {'transactionId': txId});
    if (commitRes['retryCommit'] == true) {
      return await _mutate(
        name,
        mutatorImpl,
        args,
        invokeArgs: invokeArgs,
        shouldCheckChange: shouldCheckChange,
      );
    }

    final ref = commitRes['ref'];
    if (shouldCheckChange) {
      await _checkChange(ref);
    }
    return _MutateResult(rv, ref);
  }

  Future<void> _closeTransaction(int txId) async {
    try {
      await _invoke('closeTransaction', {'transactionId': txId});
    } catch (ex) {
      error('Failed to close transaction: $ex');
    }
  }
}

class ReplicacheTest extends Replicache {
  ReplicacheTest._new({
    @required String diffServerUrl,
    String name = '',
    String dataLayerAuth = '',
    String diffServerAuth = '',
    String batchUrl = '',
    RepmInvoke repmInvoke,
  }) : super._new(
          diffServerUrl: diffServerUrl,
          name: name,
          dataLayerAuth: dataLayerAuth,
          diffServerAuth: diffServerAuth,
          batchUrl: batchUrl,
          syncInterval: null,
          repmInvoke: repmInvoke,
        );

  static Future<ReplicacheTest> make({
    @required String diffServerUrl,
    String name = '',
    String dataLayerAuth = '',
    String diffServerAuth = '',
    String batchUrl = '',
    RepmInvoke repmInvoke,
  }) async {
    final rep = ReplicacheTest._new(
      diffServerUrl: diffServerUrl,
      name: name,
      dataLayerAuth: dataLayerAuth,
      diffServerAuth: diffServerAuth,
      batchUrl: batchUrl,
      repmInvoke: repmInvoke,
    );
    await rep._opened;
    await rep._root;
    return rep;
  }

  Future<String> beginSync() => super._beginSync();

  Future<void> maybeEndSync(String syncHead) => super._maybeEndSync(syncHead);
}

class _Subscription<R> {
  final Future<R> Function(ReadTransaction tx) callback;
  final StreamController<R> streamController;
  _Subscription(this.callback, this.streamController);
}

class _SubscriptionSuccess<V> {
  final V value;
  _SubscriptionSuccess(this.value);
}

class _SubscriptionError<E> {
  final E error;
  _SubscriptionError(this.error);
}

class _MutateResult<R> {
  final R result;
  final String ref;
  _MutateResult(this.result, this.ref);
}
