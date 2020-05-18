# Development

Run `./tool/build.sh` once. This will download the correct version of the Replicache client library.

You won't need to do this again unless you want to pick up a newer version of that library.

# Testing

Unit testing is accomplished mostly in the normal Flutter fashion:

```
flutter test
```

By default, unit tests run against a mock replicache-client which
returns a pre-recorded set of responses. See [test/fixtures/](test/fixtures/).

To update the recorded fixtures you need to run the replicache-client test server:

```
go run ./build/replicache-client/cmd/test_server/main.go &
```

Then run the tests with `TEST_MODE` set to `record` like this:

```
TEST_MODE=record flutter test
```

`TEST_MODE` is one of:

- `live` - Uses the local replicicache-client test server.
- `record` - Uses the local replicicache-client test server and records the
  requests and updates the test fixtures.
- `replay` - Uses the test fixtures without talking to any server.

(default is `replay`).

# Roll Replicache Client Dependency

- Update the `REPM_VERSION` in build.sh
- Run `build.sh` again

# Release

- Tag the repo with a new version `git tag vX.Y.Z`
- Run `./build.sh`
- The release binaries are in `build`
