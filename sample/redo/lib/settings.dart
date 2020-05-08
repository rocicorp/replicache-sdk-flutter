import 'dart:io';

final diffServerUrl =
    'http://${Platform.isAndroid ? '10.0.2.2' : 'localhost'}:7001/pull';
const loginUrl = 'https://replicache-sample-todo.now.sh/serve/login';
const batchUrl = 'https://replicache-sample-todo.now.sh/serve/replicache-batch';
