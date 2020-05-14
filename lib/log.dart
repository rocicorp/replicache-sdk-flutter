/// Defines logging levels for Replicache.
enum LogLevel {
  debug,
  info,
  error,
}

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
