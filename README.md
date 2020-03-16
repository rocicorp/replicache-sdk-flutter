# Local-First Flutter Apps in Less than 5 Minutes

#### 1. Get the SDK

Download the latest [replicache-flutter-sdk.tar.gz](https://github.com/rocicorp/replicache-sdk-flutter/releases/latest/download/replicache-flutter-sdk.tar.gz), then unzip it

```
tar xvzf replicache-flutter-sdk.tar.gz
```

#### 2. Add the `replicache` dependency to your `pubspec.yaml`

```
...

  cupertino_icons: ^0.1.2

+   replicache:
+     path:
+       /tmp/replicache-flutter-sdk/

...
```

#### 3. Create a transaction bundle

You interact with Replicache by executing _transactions_, which are written in JavaScript.

Create a new `lib/bundle.js` file inside your app to hold some transactions, then add this code to it:

```
function codeVersion() {
    return 1.1;
}

function increment(delta) {
    var val = getCount();
    db.put('count', val + delta);
}

function getCount() {
    return db.get('count') || 0;
}
```

#### 4. Mark `lib/bundle.js` as an asset inside `pubspec.yaml`:

```
...

flutter:
  uses-material-design: true
  assets:
+    - lib/bundle.js

...
```

#### 5. Instantiate Replicache

```
import 'package:replicache/replicache.dart';

...

var rep = Replicache('https://serve.replicate.to/sandbox/any-name-here');
```

For now, you can use any name you want after `serve` in the URL.

#### 6. Put bundle

```dart
await rep.putBundle(
  await rootBundle.loadString('lib/bundle.js', cache: false),
);
```

#### 7. Execute transactions

```
await rep.exec('increment', [1]);
await rep.exec('increment', [41]);
var count = await rep.exec('getCount');
print('The answer is ${count}');
```

Congratulations — you are done 🎉. Time for a cup of coffee.

In fact, while you're away, why not install the app on two devices and let them sync with each other?

Disconnect them. Take a subway ride. Whatever. It's all good. The devices will sync up automatically when there is connectivity.

[Conflicts are handled naturally](https://github.com/rocicorp/replicache/blob/master/design.md#conflicts) by ordering atomic transactions consistently on all devices.

## Want something even easier?

Download the above steps as a running sample. See [flutter/hello](https://github.com/rocicorp/replicache-sdk-flutter/tree/master/sample/hello).

## Next steps

- See [`flutter/redo`](https://github.com/rocicorp/replicache-sdk-flutter/tree/master/sample/redo) a fully functioning TODO app built on Flutter and Replicache
- Review the [Replicache Dart Reference](https://flutter.doc.replicate.to/replicache/replicache-library.html)
- Review the [JavaScript API for Replicache transactions](https://github.com/rocicorp/replicache-server/blob/master/doc/transaction-api.md)
- Inspect your Replicache databases using [the `repl` tool](https://github.com/rocicorp/replicache-server/blob/master/doc/cli.md)

## More questions?

See the [design doc](https://github.com/rocicorp/replicache/blob/master/design.md).
