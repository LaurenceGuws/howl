import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server_connections.dart';

final class _MemoryStore implements HowlServerConnectionStore {
  _MemoryStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String encoded) async => value = encoded;
}

void main() {
  test('Server connections persist lifecycle and selected endpoint', () async {
    final store = _MemoryStore();
    final connections = HowlServerConnections(store);
    await connections.initialize();
    expect(connections.servers, isEmpty);
    expect(connections.selectedEndpoint, isNull);

    final home = HowlServerConnection(
      label: 'Home',
      endpoint: 'tcp://127.0.0.1:43130',
    );
    final lab = HowlServerConnection(
      label: 'Lab',
      endpoint: 'tcp://127.0.0.1:43131',
    );
    await connections.upsert(lab);
    await connections.upsert(home);
    expect(connections.servers.map((server) => server.label), <String>[
      'Home',
      'Lab',
    ]);

    await connections.select(home.endpoint);
    expect(connections.selectedEndpoint, home.endpoint);

    final movedHome = HowlServerConnection(
      label: 'Home',
      endpoint: 'tcp://127.0.0.1:43132',
    );
    await connections.upsert(movedHome, replacingEndpoint: home.endpoint);
    expect(connections.selectedEndpoint, movedHome.endpoint);
    expect(connections.find(home.endpoint), isNull);

    final reloaded = HowlServerConnections(store);
    await reloaded.initialize();
    expect(reloaded.selectedEndpoint, movedHome.endpoint);
    expect(reloaded.servers.length, 2);
    expect(reloaded.find(movedHome.endpoint)?.label, 'Home');

    await reloaded.remove(movedHome.endpoint);
    expect(reloaded.selectedEndpoint, isNull);
    expect(reloaded.servers.single.label, 'Lab');
  });

  test('Server connection model rejects duplicate and corrupt state', () async {
    final store = _MemoryStore();
    final connections = HowlServerConnections(store);
    await connections.initialize();
    await connections.upsert(
      HowlServerConnection(label: 'Home', endpoint: 'tcp://127.0.0.1:43130'),
    );
    await expectLater(
      connections.upsert(
        HowlServerConnection(label: 'Other', endpoint: 'tcp://127.0.0.1:43130'),
      ),
      throwsStateError,
    );

    final corrupt = HowlServerConnections(
      _MemoryStore(
        '{"schema":"howl.server-connections/v1","servers":['
        '{"label":"Home","endpoint":"tcp://127.0.0.1:43130"}],'
        '"selectedEndpoint":"tcp://127.0.0.1:9999"}',
      ),
    );
    await corrupt.initialize();
    expect(corrupt.servers, isEmpty);
    expect(corrupt.selectedEndpoint, isNull);
    expect(corrupt.loadError, isNotNull);
  });
}
