import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replicache/replicache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // const MethodChannel(CHANNEL_NAME)
  //     .setMockMethodCallHandler((methodCall) async {
  //   print(methodCall);
  //   switch (methodCall.method) {
  //     case 'open':
  //       return '';
  //     case 'getRoot':
  //       return json.encode({'root': ''});
  //   }
  //   // if (methodCall.method == 'getAll') {
  //   //   return <String, dynamic>{}; // set initial values here if desired
  //   // }
  //   print('Not implemented ${methodCall.method}');
  //   return null;
  // });

  test('xxx', () async {
    final rep = Replicache("remote");
    await rep.query((tx) {});
    expect(1, 1);
    expect(2, 1);
  });
}
