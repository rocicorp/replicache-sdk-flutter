# Development

Run `./tool/build.sh` once. This will download the correct version of the Replicache client library.

You won't need to do this again unless you want to pick up a newer version of that library.

# Testing

Unit testing is accomplished mostly in the normal Flutter fashion:

```
flutter test
```

By default, unit tests run against a mock replicache-client which
returns a pre-recorded set of responses. See [sync_replay.json](test/sync_replay.json).

To update the recording, modify `replicache_test.dart` thusly:

```
-    recordPath = './sync_replay.json';
-    // await useReplay('./sync_replay.json');
+    // recordPath = './sync_replay.json';
+    await useReplay('./sync_replay.json');
```

then start a replicache-client test server:

```
go run ./build/replicache-client/cmd/test_server/main.go &
```

then re-run the tests:

```
flutter test
```

**Don't forget to undo the change to `replicache_test.dart` before landing!**

# Roll Replicache Client Dependency

- Update the `REPM_VERSION` in build.sh
- Run `build.sh` again

# Release

- Tag the repo with a new version `git tag vX.Y.Z`
- Run `.build.sh`
- The release binaries are in `build`
