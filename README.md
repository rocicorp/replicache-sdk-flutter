# Replicache Flutter SDK - Quickstart

#### 1. Get the SDK

Download the [Replicache SDK](https://github.com/rocicorp/replicache/releases/latest/download/replicache-sdk.tar.gz), then unzip it:

```
tar xvzf replicache-sdk.tar.gz
```

#### 2. Start a development diff-server and put some sample data in it:

```
/path/to/replicache-sdk/diffs --enable-inject
# TODO
curl -d '{...}' http://localhost:7000/inject
```

#### 3. Add the `replicache` dependency to your Flutter app's `pubspec.yaml`

```
...

  cupertino_icons: ^0.1.2

+   replicache:
+     path:
+       /tmp/replicache-flutter-sdk/

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
}).onchange...
```

Now inject a new snapshot, you'll see your view dynamically update:

```
curl -d ...
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
