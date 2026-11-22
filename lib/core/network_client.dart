import 'package:http/http.dart' as http;

import 'network_client_stub.dart'
    if (dart.library.io) 'network_client_io.dart'
    as platform;

/// Keep one client per owner and close it when that owner is disposed.
http.Client createNetworkClient() => platform.createNetworkClient();
