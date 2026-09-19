# Logging and Diagnostics

Use the project logger and Catcher integration for diagnostics. `lib/services/logger.dart` defines the process-level `logger` with `ProductionFilter`, `PrettyLogPrinter`, and `trace` level in debug versus `warning` in release (`kDebugMode ? .trace : .warning`). This is the baseline for internal logs; it is not a replacement for a user-facing error widget.

## File reports

`JsonFileHandler` in `lib/utils/json_file_handler.dart` is a Catcher `ReportHandler`. Its static future queue is initialized from `LoggerUtils.getLogsPath()` and every `add` operation appends JSONL and flushes the `RandomAccessFile`. `JsonFileHandler.init()` returns `null` after logging an initialization failure, and `handle` reports write failures with `logger.e`.

`LoggerUtils.getLogsPath()` in `lib/services/logger.dart` creates `.pili_logs.json` under the application documents directory and caches the log `File`. `LoggerUtils.clearLogs()` respects `Pref.enableLog`: enabled logging uses the serialized `JsonFileHandler.add` path; disabled logging truncates the file directly. Keep file writes serialized rather than opening independent append streams.

## What to log

Log operation context and an exception/stack trace at the boundary where it is actionable. `Request` normalizes Dio failures for the caller, while `JsonFileHandler.handle` records report-write exceptions. In debug, the shared Dio `LogInterceptor` is enabled by `lib/http/init.dart`; release logging is intentionally quieter.

Never include cookies, access keys, refresh tokens, full authorization headers, or unredacted private payloads. `lib/main.dart` initializes storage and catches startup failures by copying text without a toast; that is a model for keeping startup recovery separate from noisy UI notifications.

## Avoid and common mistakes

- Do not use `print`; `analysis_options.yaml` enables `avoid_print`. Use `logger` or the existing debug-only diagnostic path.
- Do not add an ad-hoc file writer for a feature; use `LoggerUtils`/`JsonFileHandler` so writes are ordered and flush failures are handled.
- Do not log secrets from `lib/utils/accounts/`, cookies, request headers, or protobuf payloads merely to debug a request.
- Do not lower release logging to trace or treat debug Dio output as a production observability contract.
- Do not convert an internal exception into an automatic toast in a service; preserve diagnostics and let the UI decide whether the user needs a message.
