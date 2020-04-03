# Replicache Flutter SDK - Quickstart

Hi! This tutorial will walk you through setting up the [Replicache](https://replicache.dev) client for Flutter as quickly as possible. For more detail on how Replicache works, see the [design document](https://github.com/rocicorp/replicache/blob/master/design.md).

#### 1. Get the SDK

Download the [Replicache SDK](https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz), then unzip it:

```
tar xvzf replicache-sdk.tar.gz
```

#### 2. Start a development diff-server and put some sample data in it:

Under normal circumstances, Replicache periodically pulls a snapshot of user data that should be persistent on the client (the *Client View*) from your service. Replicache computes a diff for each client and sends only the changes as part of downstream sync.

You will need set up integration with your service later (see [server-side integration](https://github.com/rocicorp/replicache/blob/master/README.md)).

But while you're working on the client side, it's easiest to just inject snapshots directly from the command line:

```
/path/to/replicache-sdk/<platform>/diffs --enable-inject
curl -d '{"accountID":"sandbox", "clientID":"c1", "clientViewResponse":{"clientView":{"foo":"bar"},"lastTransactionID":"0"}}' http://localhost:7001/inject
```

#### 3. Add the `replicache` dependency to your Flutter app's `pubspec.yaml`

```
...

  cupertino_icons: ^0.1.2

+   replicache:
+     path:
+       /path/to/replicache-sdk/flutter/

...
```

#### 4. Instantiate Replicache

```
import 'package:replicache/replicache.dart';

...
var rep = Replicache(
  // The Replicache diff-server to talk to.
  'http://localhost:7000',

  // Your server, where the /replicache-client-view and /replicache-batch handlers are.
  'http://localhost:8000');
```

#### 5. Read Data

```
rep.subscribe((tx) {
}).onChange...
```

Now inject a new snapshot, you'll see your view dynamically update:

```
curl -d '{"accountID":"sandbox", "clientID":"c1", "clientViewResponse":{"clientView":{"foo":"baz", "hot": "dog"},"lastTransactionID":"0"}}' http://localhost:7001/inject
```

Nice!

#### 6. Write Data

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
