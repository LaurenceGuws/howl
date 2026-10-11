import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server_connections.dart';

final class GatedStore implements HowlServerConnectionStore {
  String? value;
  Completer<String?>? readGate;
  Completer<void>? writeGate;
  bool readFails = false;
  bool writeFails = false;
  int reads = 0;
  int writes = 0;
  @override
  Future<String?> read() async {
    reads++;
    if (readFails) throw StateError('read failed');
    return readGate == null ? value : await readGate!.future;
  }

  @override
  Future<void> write(String encoded) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (writeFails) throw StateError('write failed');
    value = encoded;
  }
}

void main() {
  final a = HowlServerConnection(label: 'A', endpoint: 'tcp://127.0.0.1:41001');
  final b = HowlServerConnection(label: 'B', endpoint: 'tcp://127.0.0.1:41002');

  test(
    'remove B then select B cannot restore B in memory or on disk',
    () async {
      final store = GatedStore();
      final model = HowlServerConnections(store);
      addTearDown(model.dispose);
      await model.initialize();
      await model.upsert(a);
      await model.upsert(b);
      final gate = store.writeGate = Completer<void>();
      final remove = model.remove(b.endpoint);
      final select = expectLater(model.select(b.endpoint), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 3); // only the removal has entered persistence
      gate.complete();
      await remove;
      await select;
      expect(model.servers.map((s) => s.endpoint), [a.endpoint]);
      expect(model.selectedEndpoint, isNull);
      final reload = HowlServerConnections(store);
      addTearDown(reload.dispose);
      await reload.initialize();
      expect(reload.servers.map((s) => s.endpoint), [a.endpoint]);
      expect(reload.selectedEndpoint, isNull);
    },
  );

  test('overlapping upserts derive from committed predecessor', () async {
    final store = GatedStore()..writeGate = Completer<void>();
    final model = HowlServerConnections(store);
    addTearDown(model.dispose);
    await model.initialize();
    final first = model.upsert(a);
    final second = model.upsert(b);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(model.servers, isEmpty);
    store.writeGate!.complete();
    await Future.wait([first, second]);
    expect(model.servers.map((s) => s.endpoint), [a.endpoint, b.endpoint]);
  });

  test(
    'failed write publishes nothing and does not poison transaction tail',
    () async {
      final store = GatedStore();
      final model = HowlServerConnections(store);
      addTearDown(model.dispose);
      await model.initialize();
      await model.upsert(a);
      final committed = store.value;
      var notifications = 0;
      model.addListener(() => notifications++);
      store.writeFails = true;
      await expectLater(model.remove(a.endpoint), throwsStateError);
      expect(store.value, committed);
      expect(model.find(a.endpoint), isNotNull);
      expect(notifications, 0);
      store.writeFails = false;
      await model.upsert(b);
      expect(model.servers.length, 2);
      expect(notifications, 1);
    },
  );

  test(
    'duplicate initialization shares future and settles only once',
    () async {
      final store = GatedStore()..readGate = Completer<String?>();
      final model = HowlServerConnections(store);
      addTearDown(model.dispose);
      var notifications = 0;
      model.addListener(() => notifications++);
      final first = model.initialize();
      final second = model.initialize();
      expect(identical(first, second), isTrue);
      expect(store.reads, 1);
      store.readGate!.complete(null);
      await Future.wait([first, second]);
      await model.initialize();
      expect(model.initialized, isTrue);
      expect(notifications, 1);
      expect(store.reads, 1);
    },
  );

  test('delayed read after disposal neither publishes nor notifies', () async {
    final store = GatedStore()..readGate = Completer<String?>();
    final model = HowlServerConnections(store);
    var notifications = 0;
    model.addListener(() => notifications++);
    final pending = model.initialize();
    model.dispose();
    store.readGate!.complete(null);
    await pending;
    expect(notifications, 0);
  });

  test(
    'read failure settles, preserves unread config, and explicitly recovers',
    () async {
      final store = GatedStore();
      final original = HowlServerConnections(store);
      await original.initialize();
      await original.upsert(a);
      original.dispose();
      final encoded = store.value;
      store.readFails = true;
      final model = HowlServerConnections(store);
      addTearDown(model.dispose);
      await model.initialize();
      expect(model.initialized, isTrue);
      expect(model.loadError, isNotNull);
      expect(model.servers, isEmpty);
      await expectLater(model.upsert(b), throwsStateError);
      expect(store.value, encoded);
      store.readFails = false;
      await model.retryLoad();
      expect(model.loadError, isNull);
      expect(model.find(a.endpoint), isNotNull);
      await model.upsert(b);
      expect(model.servers.length, 2);
    },
  );

  test('delayed write after disposal settles without notifier use', () async {
    final store = GatedStore()..writeGate = Completer<void>();
    final model = HowlServerConnections(store);
    await model.initialize();
    final pending = model.upsert(a);
    await Future<void>.delayed(Duration.zero);
    model.dispose();
    store.writeGate!.complete();
    await pending;
    expect(store.value, isNotNull);
  });
}
