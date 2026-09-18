# PiliPlus Backend Integration Guidelines

> Project-specific guidance for the client integration and persistence layer. This Flutter repository has no server process, remote ORM, relational database, or migration system; “backend” here means HTTP/gRPC/TCP transport, app services, utilities, and Hive CE local persistence.

## Pre-Development Checklist

Before changing integration or persistence code:

- [ ] Identify the domain facade under `lib/http/`, `lib/grpc/`, or `lib/tcp/`; keep transport details out of pages and widgets.
- [ ] Trace the full contract: facade -> `Request`/`GrpcReq` -> `LoadingState<T>` -> GetX controller Rx -> `Obx` view.
- [ ] For durable state, identify the owning `GStorage` box, `Pref` accessor, and key in `lib/utils/storage_key.dart`.
- [ ] Check whether a read-modify-write can overlap; use an existing serialized queue pattern such as `LocalSubscriptions._serialized`.
- [ ] Confirm generated protobuf/Hive/JNI files are read-only boundaries and locate the hand-authored source instead.
- [ ] Plan response-envelope, transport, parse, empty, and retry behavior before editing.

## Guides

| Guide | Focus |
|---|---|
| [Directory Structure](./directory-structure.md) | HTTP/gRPC/TCP/services/utils, model locations, and generated boundaries |
| [Database Guidelines](./database-guidelines.md) | Hive CE boxes, `GStorage`, `Pref`, key ownership, and serialized writes; no server database |
| [Error Handling](./error-handling.md) | Dio normalization, API envelopes, gRPC status, `LoadingState`, and user reporting |
| [Quality Guidelines](./quality-guidelines.md) | Analyzer rules, async/resource ownership, generated code, tests, and review gates |
| [Logging Guidelines](./logging-guidelines.md) | Logger levels, Catcher JSON reports, serialized file writes, and secret safety |

## Quality checks

- [ ] Every new integration API has a typed `LoadingState<T>` contract and preserves actionable error messages.
- [ ] HTTP APIs check their domain envelope; gRPC APIs honor `Grpc-Status` and parser failures.
- [ ] Storage is initialized through `GStorage.init()`, adapters are registered, and existing keys/boxes are reused.
- [ ] Async writes/resources are awaited, serialized where needed, and closed/disposed by their owner.
- [ ] Diagnostics use `logger`/Catcher without leaking cookies, tokens, or private payloads.
- [ ] No generated output, application Dart behavior outside the requested integration change, or relative imports were altered.

Read the linked guide before implementation and use the shared thinking guides in `.trellis/spec/guides/` when work crosses transport, state, and persistence boundaries. All guidance is English and grounded in the current source tree.
