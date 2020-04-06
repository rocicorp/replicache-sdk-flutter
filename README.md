# Replicache Flutter SDK - Quickstart

Hi! This tutorial will walk you through setting up Replicache for Flutter as quickly as possible.

**Note:** This document assumes you already know what Replicache is, why you might need it, and broadly how it works. If that's not true, see the [Replicache homepage](https://replicache.dev) for an overview, or the [design document](https://github.com/rocicorp/replicache/blob/master/design.md) for a detailed deep-dive.

#### 1. Get the SDK

Download the [Replicache SDK](https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz), then unzip it:

```
tar xvzf replicache-sdk.tar.gz
```

#### 2. Add the `replicache` dependency to your Flutter app's `pubspec.yaml`

```
...

  cupertino_icons: ^0.1.2

+   replicache:
+     path:
+       /path/to/replicache-sdk/flutter/

...
```

#### 3. Instantiate Replicache

```
import 'package:replicache/replicache.dart';

...
var rep = Replicache(
  // The Replicache diff-server to talk to - we will start this in the next step.
  'http://localhost:7000',
  
  // Optional: pass an auth token to access /replicache-client-view on your server
  // This will be sent by Replicache in the Authorization header.
  clientViewAuth: yourAuthToken);
```

#### 4. Start a development diff-server and put some sample data in it:

Under normal circumstances, Replicache periodically pulls a snapshot of user data that should be persistent on the client (the *Client View*) from your service. Replicache computes a diff for each client and sends only the changes as part of downstream sync.

You will need set up integration with your service later (see [server-side integration](https://github.com/rocicorp/replicache/blob/master/README.md)).

But while you're working on the client side, it's easiest to just inject snapshots directly from the command line:

```
/path/to/replicache-sdk/<platform>/diffs --enable-inject

curl -d @- http://localhost:7001/inject << EOF
{
  # The account to modify. For development, use "sandbox".
  "accountID": "sandbox",
  # The clientID of the cache to modify. diff-server tracks a unique cache for every unique client.
  # TODO: How do we get this?
  "clientID": "c1",
  "clientViewResponse": {
    "clientView": {
      # Put any key/value pairs you like in here.
      "firstKey": "originalValue"
    },
    # Must be zero for now. See mutation section below.
    "lastTransactionID":"0"
  }
}
EOF

```

#### 5. Read Data

```
class _MyHomePageState extends State<MyHomePage> {
  List<String> _todos;
  Replicache _rep;

  _MyHomePageState() {
    ...
    _rep.onChange = this._handleChange;
    _handleChange();
  }

  void _handleChange() async {
    // TODO
    let todos = await _rep.scan("/todo/")...
    setState(() {
      _todos = todos;
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.display1,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}
```

#### 6. Update Data

Now inject a new snapshot, you'll see your view dynamically update:

```
curl -d @- http://localhost:7001/inject << EOF
{
  "accountID": "sandbox",
  "clientID": "c1",
  "clientViewResponse": {
    "clientView": {
      # Put any key/value pairs you like in here.
      "firstKey": "originalValue"
    },
    # Must be zero for now. See mutation section below.
    "lastTransactionID":"0"
  }
}
EOF
```

Nice!

#### 7. Write Data

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
