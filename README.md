# Replicache Flutter SDK

![Flutter Test](https://github.com/rocicorp/replicache-sdk-flutter/workflows/Flutter%20Test/badge.svg)

# Quickstart

Hi! This tutorial will walk you through integrating Replicache into your Flutter mobile app.

If you have any problems working through this, or just have questions, please [join us on Slack](https://join.slack.com/t/rocicorp/shared_invite/zt-ekh3oxbq-FzzB7qP9lwqdTvBjxXU2oA). We'd be happy to help. See also our [contributing guide](https://github.com/rocicorp/replicache/blob/master/contributing.md).

# Contributing

See the [contributing guide in the main Replicache repo]


**Note:** This document assumes you already know what Replicache is, why you might need it, and broadly how it works. If that's not true, see the [Replicache homepage](https://replicache.dev) for an overview, or the [design document](https://github.com/rocicorp/replicache/blob/master/design.md) for a detailed deep-dive.

### 1. Get the SDK

Download the [Replicache SDK](https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz), then unzip it:

```bash
curl -o replicache-sdk.tar.gz -L https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz
tar xvzf replicache-sdk.tar.gz
```

### 2. Start a new, empty Flutter app

```bash
flutter create todo
```

### 3. Add the `replicache` dependency to your Flutter app's `pubspec.yaml`

```yaml
...

  cupertino_icons: ^0.1.2

+   replicache:
+     path:
+       /path/to/replicache-sdk/flutter/

...
```

### 4. Add main.dart

Replace the contents of `main.dart` with the following:

```dart
import 'package:flutter/material.dart';
import 'package:replicache/replicache.dart';
import 'dart:io';
import 'dart:math';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  final String _title = 'Replicache Demo';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _title,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: _title),
    );
  }
}

class MyHomePage extends StatelessWidget {
  final String title;
  // Android emulator cannot use localhost.
  final diffsURL = 'http://${Platform.isAndroid ? '10.0.2.2' : 'localhost'}:7001/pull';
  final _random = Random();
  Replicache _replicache;
  Mutator _createTodo;

  MyHomePage({Key key, this.title}) : super(key: key) {
    _replicache = Replicache(diffsURL);
    _createTodo = _replicache.register("createTodo", (tx, args) async {
      tx.put("/todo/${args["id"]}", args);
    });
  }

  void _handleAddTodo() {
    var id = _random.nextInt(2^32-1);
    _createTodo({"id": id, "text": "Todo $id", "order": 1.0, "complete": false});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Todo',
            onPressed: () {
              _handleAddTodo();
            },
          ),
        ],
      ),
      body: Center(
        child: StreamBuilder(
          stream: _replicache.subscribe((ReadTransaction tx) async {
            Iterable<ScanItem> res = await tx.scan(prefix: '/todo/');
            return res.map((event) => event.value as Map<String, dynamic>);
          }),
          builder:  (BuildContext context, AsyncSnapshot<Iterable<Map<String, dynamic>>> snapshot) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.from(
                (snapshot.data ?? []).map(
                  (Map m) => CheckboxListTile(value: m['complete'], title: Text(m['text'])))),
            );
          },
        ),
      ),
    );
  }
}
```

Now launch the Flutter app:

```bash
cd todo
flutter pub get
flutter emulators --launch apple_ios_simulator
flutter run
```

You will see Replicache start up and start trying to sync, but fail because no diff-server is running. That's OK! We'll fix that in the next step.

For now, search for `ClientID` in the output and copy it down. Every device syncing with Replicache has a unique `ClientID` generated at first run. We'll need that value next.


### 5. Start a development diff-server and put some sample data in it:

Under normal circumstances, Replicache periodically pulls a snapshot of user data that should be persistent on the client (the *Client View*) from your service. Replicache computes a diff for each client and sends only the changes as part of downstream sync.

You will need set up integration with your service later (see [server-side integration](https://github.com/rocicorp/replicache/blob/master/README.md)).

But while you're working on the client side, it's easiest to just inject snapshots directly from the command line.

In a new tab, start a development `diffs` server and leave it running:

```bash
/path/to/replicache-sdk/<platform>/diffs --db=/tmp/foo serve --enable-inject
```

Then, in a third tab, inject a snapshot into the diff server:

```bash
CLIENT_ID=<your-client-id-from-step-4>
curl -d @- http://localhost:7001/inject << EOF
{
  "accountID": "sandbox",
  "clientID": "$CLIENT_ID",
  "clientViewResponse": {
    "clientView": {
      "/list/29597": {
        "id": 29597,
        "ownerUserID": 3
      },
      "/todo/14136": {
        "complete": false,
        "id": 14136,
        "listId": 29597,
        "order": 0.5,
        "text": "Take out the trash"
      },
      "lastTransactionID":"0"
    }
  }
}
EOF
```

Notes:

* To get the `clientID` value search the log output of the Flutter app for `ClientID`. Replicache prints it out early in startup.
* The `accountID` is your unique account ID on diff-server. During our early alpha testing, use "sandbox".
* You'll setup `lastTransactionID` later in this tutorial. For now just return `0`.

### 6. Update Data

Now inject a new snapshot, you'll see your view dynamically update:

```bash
curl -d @- http://localhost:7001/inject << EOF
{
  "accountID": "sandbox",
  "clientID": "$CLIENT_ID",
  "clientViewResponse": {
    "clientView": {
      "/list/29597": {
        "id": 29597,
        "ownerUserID": 3
      },
      "/todo/14136": {
        "complete": true,
        "id": 14136,
        "listId": 29597,
        "order": 0.5,
        "text": "Take out the trash"
      },
      "/todo/9081": {
        "complete": false,
        "id": 9081,
        "listId": 29597,
        "order": 0.75,
        "text": "Walk the dog"
      },
      "lastTransactionID":"0"
    }
  }
}
EOF
```

You will see the Flutter app update and display a new TODO and check off the previous one. Nice!

### 7. Write Data

Add a Todo by pressing the "+" button in the top-right corner of the app. Periodically the client will attempt to sync and push this change to the server.


### 8. 🎉

Congratulations — you are done with the client setup! Time for a cup of coffee.

In fact, while you're away, why not turn off the wifi and click around. Your app will respond instantly with cached data and queue up the changes to replay, once you setup the server-side integration.

## Next steps

- Implement the [server-side of Replicache integration](https://github.com/rocicorp/replicache/)
- See [`flutter/redo`](https://github.com/rocicorp/replicache-sdk-flutter/tree/master/sample/redo) a fully functioning TODO app built on Flutter and Replicache
- Review the [Replicache Dart Reference](https://replicache-sdk-flutter.now.sh/)
- Inspect your Replicache databases using [the `repl` tool](https://github.com/rocicorp/replicache-server/blob/master/doc/cli.md)

## More questions?

* [Join us on Slack!](https://join.slack.com/t/rocicorp/shared_invite/zt-ekh3oxbq-FzzB7qP9lwqdTvBjxXU2oA)
* See the [design doc](https://github.com/rocicorp/replicache/blob/master/design.md).
