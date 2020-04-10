# Replicache Flutter SDK - Quickstart

Hi! This tutorial will walk you through integrating Replicache into your Flutter mobile app.

If you have any problems working through this, or just have questions, please [join us on Slack](https://join.slack.com/t/rocicorp/shared_invite/zt-dcez2xsi-nAhW1Lt~32Y3~~y54pMV0g). We'd be happy to help.

**Note:** This document assumes you already know what Replicache is, why you might need it, and broadly how it works. If that's not true, see the [Replicache homepage](https://replicache.dev) for an overview, or the [design document](https://github.com/rocicorp/replicache/blob/master/design.md) for a detailed deep-dive.

#### 1. Get the SDK

Download the [Replicache SDK](https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz), then unzip it:

```
curl -o replicache-sdk.tar.gz -L https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz
tar xvzf replicache-sdk.tar.gz
```

#### 2. Start a new, empty Flutter app

```
flutter create todo
```

#### 3. Add the `replicache` dependency to your Flutter app's `pubspec.yaml`

```
...

  cupertino_icons: ^0.1.2

+   replicache:
+     path:
+       /path/to/replicache-sdk/replicache-flutter-sdk/

...
```

#### 4. Instantiate Replicache

```
import 'package:replicache/replicache.dart';

...
var rep = Replicache(
  // The Replicache diff-server to talk to - we will start this in the next step.
  'http://localhost:7001',
  
  // Optional: pass an auth token to access /replicache-client-view on your server
  // This will be sent by Replicache in the Authorization header.
  clientViewAuth: yourAuthToken);
```

#### 5. Start a development diff-server and put some sample data in it:

Under normal circumstances, Replicache periodically pulls a snapshot of user data that should be persistent on the client (the *Client View*) from your service. Replicache computes a diff for each client and sends only the changes as part of downstream sync.

You will need set up integration with your service later (see [server-side integration](https://github.com/rocicorp/replicache/blob/master/README.md)).

But while you're working on the client side, it's easiest to just inject snapshots directly from the command line.

First start a development `diffs` server:

```bash
/path/to/replicache-sdk/<platform>/diffs --db=/tmp/foo serve --enable-inject
```

Then inject a snapshot into it:

```bash
curl -d @- http://localhost:7001/inject << EOF
{
  "accountID": "sandbox",
  "clientID": <your-client-id>,
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
        "text": "Take out the trash",
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

#### 6. Read Data

```dart
class _MyHomePageState extends State<MyHomePage> {
  List<Map<String, dynamic>> _events = [];
  Replicache _replicache = new Replicache('http://localhost:7001');

  _MyHomePageState() {
    _replicache.onChange = _handleChange;
    _handleChange();
  }
  
  void _handleChange() async {
    var events = List<Map<String, dynamic>>.from(
      (await _replicache.scan(prefix: '/todo/')).map((item) => item.value));
    setState(() {
      _events = events;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.from(
            _events.map(
              (Map m) => CheckboxListTile(value: m['complete'], title: Text(m['text'])))),
        ),
      ),
    );
  }
}
```

#### 7. Update Data

Now inject a new snapshot, you'll see your view dynamically update:

```bash
curl -d @- http://localhost:7001/inject << EOF
{
  "accountID": "sandbox",
  "clientID": <your-client-id>,
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
        "text": "Take out the trash",
      },
      "/todo/9081": {
        "complete": false,
        "id": 9081,
        "listId": 29597,
        "order": 0.75,
        "text": "Walk the dog",
      },
      "lastTransactionID":"0"
    }
  }
}
EOF
```

Nice!

#### 8. Write Data

TODO (this isn't implemented in the SDK yet)


Congratulations — you are done with the client setup 🎉. Time for a cup of coffee.

In fact, while you're away, why not turn off the wifi and click around. Your app will respond instantly with cached data and queue up the changes to replay, once you setup the server-side integration.

## Next steps

- Implement the [server-side of Replicache integration](https://github.com/rocicorp/replicache/)
- See [`flutter/redo`](https://github.com/rocicorp/replicache-sdk-flutter/tree/master/sample/redo) a fully functioning TODO app built on Flutter and Replicache
- Review the [Replicache Dart Reference](https://flutter.doc.replicate.to/replicache/replicache-library.html)
- Inspect your Replicache databases using [the `repl` tool](https://github.com/rocicorp/replicache-server/blob/master/doc/cli.md)

## More questions?

* [Join us on Slack!](#TODO)
* See the [design doc](https://github.com/rocicorp/replicache/blob/master/design.md).
