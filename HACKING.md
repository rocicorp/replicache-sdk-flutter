# Development

Run `./tool/build.sh` once. This will download the correct version of the Replicant client library.

You won't need to do this again unless you want to pick up a newer version of that library.

Get the [`repl` command line](https://github.com/rocicorp/replicant/releases) and start a dev server:

```
repl --db=/tmp/wherever serve
```

Once you've done this, you can run the sample apps (in `sample` directory) and they will pick up Dart changes
in the library as you make them.

# Roll Replicant Client Dependency

* Update the `REPM_VERSION` in build.sh
* Run `build.sh` again

# Release

* Tag the repo with a new version `git tag vX.Y.Z`
* Run `.build.sh`
* The release binaries are in `build`
