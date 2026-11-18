import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The development CA certificate: the base64 body of its PEM, on one line
/// (Flutter can't pass build values containing newlines on Windows hosts).
const String _devCaCert = String.fromEnvironment('DEV_CA_CERT');

/// Adds the development CA (if one was supplied at build time) to the trust
/// store of every [HttpClient] the app creates. That covers Dio and
/// WebSockets, which both build on [HttpClient].
///
/// The public roots stay trusted, and no certificate check is ever skipped:
/// a certificate must still chain to a trusted root and match the host name.
void installDevCaTrust() {
  // Release builds trust public CAs only, whatever was passed at build time.
  if (_devCaCert.isEmpty || kReleaseMode) return;
  HttpOverrides.global = _DevCaHttpOverrides(
    SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(utf8.encode(_pem(_devCaCert))),
  );
}

String _pem(String base64Body) {
  final lines = [
    for (var i = 0; i < base64Body.length; i += 64)
      base64Body.substring(i, (i + 64).clamp(0, base64Body.length)),
  ];
  return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n';
}

class _DevCaHttpOverrides extends HttpOverrides {
  _DevCaHttpOverrides(this._context);

  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _context);
}
