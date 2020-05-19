import 'scan_bound.dart';
import 'scan_item.dart';

/// ReadTransactions are used with [Replicache.query] and allows read operations on the database.
abstract class ReadTransaction {
  /// Get a single value from the database.
  Future<dynamic> get(String key);

  /// Determines if a single key is present in the database.
  Future<bool> has(String key);

  /// Gets many values from the database.
  Future<Iterable<ScanItem>> scan({String prefix, ScanBound start, int limit});
}

typedef Future<dynamic> _Invoke(String rpc, [dynamic args]);

class ReadTransactionImpl implements ReadTransaction {
  final int _transactionId;
  final _Invoke _invoke;

  ReadTransactionImpl(this._invoke, this._transactionId);

  Future<dynamic> get(String key) async {
    final result = await _invoke('get', {
      'transactionId': _transactionId,
      'key': key,
    });
    if (!result['has']) {
      return null;
    }
    return result['value'];
  }

  Future<bool> has(String key) async {
    final result = await _invoke('has', {
      'transactionId': _transactionId,
      'key': key,
    });
    return result['has'];
  }

  Future<Iterable<ScanItem>> scan({
    String prefix = '',
    ScanBound start,
    int limit = 50,
  }) async {
    final args = {
      'transactionId': _transactionId,
      'prefix': prefix,
      'limit': limit,
    };
    if (start != null) {
      args['start'] = start;
    }
    List<dynamic> r = await _invoke('scan', args);
    return r.map((e) => ScanItem.fromJson(e));
  }
}

/// WriteTransactions are used with [Replicache.register] and allows read and
/// write operations on the database.
class WriteTransaction extends ReadTransactionImpl {
  WriteTransaction._new(_Invoke invoke, int transactionId)
      : super(invoke, transactionId);

  /// Sets a single value in the database. The [value] will be encoded using
  /// [json.encode].
  Future<void> put(String key, dynamic value) async {
    await _invoke('put', {
      'transactionId': _transactionId,
      'key': key,
      'value': value,
    });
  }

  /// Removes a key and its value from the database. Returns true if there was a
  /// key to remove.
  Future<bool> del(String key) async {
    final result = await _invoke('del', {
      'transactionId': _transactionId,
      'key': key,
    });
    return result['ok'];
  }
}

WriteTransaction newWriteTransaction(_Invoke invoke, int transactionId) =>
    WriteTransaction._new(invoke, transactionId);
