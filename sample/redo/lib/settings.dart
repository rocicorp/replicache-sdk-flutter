import 'dart:io';

String db = 'http://${Platform.isAndroid ? '10.0.2.2' : 'localhost'}:7001';
String loginUrl = 'https://replicache-sample-todo.now.sh/serve/login';
String auth = "";
