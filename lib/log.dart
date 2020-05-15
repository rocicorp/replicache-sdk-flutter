/// Defines logging levels for Replicache.
enum LogLevel {
  debug,
  info,
  error,
}

// WARNING: This default here is coupled to the default in replicache-client.
// They need to be changed together because there's no static initialization in
// Dart so there's no convenient place to set the initial replicache-client
// loglevel early.
LogLevel globalLogLevel = LogLevel.info;

void _log(LogLevel level, String msg) {
  if (level.index >= globalLogLevel.index) {
    print('Replicache: ${level}: ${msg}');
  }
}

void debug(String msg) {
  _log(LogLevel.debug, msg);
}

void info(String msg) {
  _log(LogLevel.info, msg);
}

void error(String msg) {
  _log(LogLevel.error, msg);
}
