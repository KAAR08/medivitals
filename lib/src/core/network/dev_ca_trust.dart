/// Lets a build trust the local gateway's development CA.
///
/// Dart's HTTP and WebSocket clients don't use Android's trust settings, so
/// the CA is passed in at build time instead:
///
///   python scripts/export_dev_ca.py      # writes secrets/dev_ca.json
///   flutter run --dart-define-from-file=secrets/dev_ca.json ...
///
/// Ignored in release builds: those trust public CAs only.
library;

export 'dev_ca_trust_stub.dart' if (dart.library.io) 'dev_ca_trust_io.dart';
