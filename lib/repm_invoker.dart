import 'dart:core';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart';

const CHANNEL_NAME = 'replicache.dev';

typedef Future<dynamic> RepmInvoke(String dbName, String rpc, [dynamic args]);

abstract class _RepmInvoker {
  Future<dynamic> invoke(String dbName, String rpc, [dynamic args]);
}

class RepmMethodChannelInvoker implements _RepmInvoker {
  static MethodChannel _channel;
  static final _encoder = JsonUtf8Encoder();

  RepmMethodChannelInvoker() {
    if (_channel == null) {
      _channel = MethodChannel(CHANNEL_NAME);
      _channel.setMethodCallHandler(methodChannelHandler);
    }
  }

  @override
  Future<dynamic> invoke(String dbName, String rpc, [dynamic args]) async {
    try {
      final r =
          await _channel.invokeMethod(rpc, [dbName, _encoder.convert(args)]);
      return r == '' ? null : jsonDecode(r);
    } catch (e) {
      throw Exception('Error invoking "$rpc": ${e.toString()}');
    }
  }

  Future<void> methodChannelHandler(MethodCall call) {
    if (call.method == 'log') {
      print('Replicache (native): ${call.arguments}');
      return Future.value();
    }
    throw Exception('Unknown method: ${call.method}');
  }
}

class RepmHttpInvoker implements _RepmInvoker {
  final String _url;
  static final _encoder = JsonUtf8Encoder();

  RepmHttpInvoker(this._url);

  @override
  Future<dynamic> invoke(String dbName, String rpc, [dynamic args]) async {
    final Uint8List data = _encoder.convert(args);
    final resp = await post('$_url/?dbname=$dbName&rpc=$rpc', body: data);
    if (resp.statusCode == HttpStatus.ok) {
      if (resp.body.isNotEmpty) {
        return json.decode(resp.body);
      }
      return '';
    }
    throw Exception(
        'Test server failed: ${resp.statusCode} ${resp.reasonPhrase}: ${resp.body}');
  }
}
