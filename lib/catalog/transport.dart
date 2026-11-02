import 'transport_stub.dart'
    if (dart.library.io) 'transport_io.dart'
    if (dart.library.js_interop) 'transport_web.dart'
    as platform;
export 'transport_protocol.dart';
import 'transport_protocol.dart';

JsonTransport createTransport() => platform.createTransport();
