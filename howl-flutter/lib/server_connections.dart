import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'howl_endpoint.dart';

@immutable
final class HowlServerConnection {
  HowlServerConnection({required String label, required String endpoint})
    : label = _normalizeLabel(label),
      endpoint = HowlEndpoint.parse(endpoint).toString();

  final String label;
  final String endpoint;

  static String _normalizeLabel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 80) {
      throw ArgumentError.value(value, 'label', 'invalid Server label');
    }
    return normalized;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'endpoint': endpoint,
  };

  static HowlServerConnection fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Server connection must be object');
    }
    final value = Map<String, Object?>.from(raw);
    const keys = <String>{'label', 'endpoint'};
    if (value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['label'] is! String ||
        value['endpoint'] is! String) {
      throw const FormatException('invalid Server connection');
    }
    try {
      return HowlServerConnection(
        label: value['label']! as String,
        endpoint: value['endpoint']! as String,
      );
    } on ArgumentError {
      throw const FormatException('invalid Server connection');
    } on HowlEndpointException {
      throw const FormatException('invalid Server endpoint');
    }
  }
}

abstract interface class HowlServerConnectionStore {
  Future<String?> read();
  Future<void> write(String encoded);
}

final class SharedPreferencesHowlServerConnectionStore
    implements HowlServerConnectionStore {
  SharedPreferencesHowlServerConnectionStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const String key = 'howl_flutter.server_connections.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(key);

  @override
  Future<void> write(String encoded) => _preferences.setString(key, encoded);
}

final class HowlServerConnections extends ChangeNotifier {
  HowlServerConnections(this._store);

  static const int maximumServers = 16;
  static const int maximumEncodedBytes = 16 * 1024;

  final HowlServerConnectionStore _store;
  List<HowlServerConnection> _servers = const <HowlServerConnection>[];
  String? _selectedEndpoint;
  String? _loadError;
  bool _initialized = false;
  bool _disposed = false;
  bool _readFailed = false;
  Future<void>? _initialization;
  Future<void> _transactions = Future<void>.value();

  bool get initialized => _initialized;
  UnmodifiableListView<HowlServerConnection> get servers =>
      UnmodifiableListView<HowlServerConnection>(_servers);
  String? get selectedEndpoint => _selectedEndpoint;
  String? get loadError => _loadError;

  HowlServerConnection? find(String endpoint) {
    for (final server in _servers) {
      if (server.endpoint == endpoint) return server;
    }
    return null;
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final encoded = await _store.read();
      if (_disposed) return;
      _readFailed = false;
      try {
        if (encoded != null) _load(encoded);
        _loadError = null;
      } catch (_) {
        _loadError = 'Saved Server connections could not be decoded';
      }
    } catch (_) {
      if (_disposed) return;
      _readFailed = true;
      _loadError = 'Saved Server connections could not be read. Retry loading before editing.';
    }
    if (_disposed) return;
    _initialized = true;
    notifyListeners();
  }

  /// A failed read must never authorize overwriting configuration we did not see.
  Future<void> retryLoad() => _transaction(() async {
    if (!_readFailed) return;
    _initialization = _initialize();
    await _initialization;
  });

  Future<void> _transaction(Future<void> Function() mutation) {
    final result = _transactions.then((_) async {
      if (_disposed) throw StateError('Server connections disposed');
      await mutation();
    });
    // Failure belongs to this caller, not to the next transaction.
    _transactions = result.catchError((Object _) {});
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> upsert(
    HowlServerConnection server, {
    String? replacingEndpoint,
  }) => _transaction(() async {
    _requireInitialized();
    final next = List<HowlServerConnection>.of(_servers);
    var index = replacingEndpoint == null
        ? -1
        : next.indexWhere((value) => value.endpoint == replacingEndpoint);
    final duplicate = next.indexWhere(
      (value) => value.endpoint == server.endpoint,
    );
    if (duplicate >= 0 && duplicate != index) {
      throw StateError('Server endpoint already configured');
    }
    if (index < 0) {
      if (next.length >= maximumServers) {
        throw StateError('Server limit reached');
      }
      next.add(server);
    } else {
      next[index] = server;
    }
    next.sort(_compareServers);
    var selected = _selectedEndpoint;
    if (replacingEndpoint != null && selected == replacingEndpoint) {
      selected = server.endpoint;
    }
    await _persist(servers: next, selectedEndpoint: selected);
    _servers = List.unmodifiable(next);
    _selectedEndpoint = selected;
    _loadError = null;
    _publish();
  });

  Future<void> remove(String endpoint) => _transaction(() async {
    _requireInitialized();
    final next = _servers
        .where((server) => server.endpoint != endpoint)
        .toList(growable: false);
    if (next.length == _servers.length) return;
    final selected = _selectedEndpoint == endpoint ? null : _selectedEndpoint;
    await _persist(servers: next, selectedEndpoint: selected);
    _servers = List.unmodifiable(next);
    _selectedEndpoint = selected;
    _loadError = null;
    _publish();
  });

  Future<void> select(String? endpoint) => _transaction(() async {
    _requireInitialized();
    if (endpoint != null && find(endpoint) == null) {
      throw StateError('Server endpoint is not configured');
    }
    if (_selectedEndpoint == endpoint) return;
    await _persist(selectedEndpoint: endpoint);
    _selectedEndpoint = endpoint;
    _publish();
  });

  void _load(String encoded) {
    if (utf8.encode(encoded).length > maximumEncodedBytes) {
      throw const FormatException('configuration too large');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('configuration must be object');
    }
    final value = Map<String, Object?>.from(decoded);
    const keys = <String>{'schema', 'servers', 'selectedEndpoint'};
    if (value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['schema'] != 'howl.server-connections/v1' ||
        value['servers'] is! List ||
        (value['selectedEndpoint'] != null &&
            value['selectedEndpoint'] is! String)) {
      throw const FormatException('invalid configuration');
    }
    final servers =
        (value['servers']! as List)
            .map(HowlServerConnection.fromJson)
            .toList(growable: false)
          ..sort(_compareServers);
    if (servers.length > maximumServers) {
      throw const FormatException('too many Servers');
    }
    final endpoints = <String>{};
    for (final server in servers) {
      if (!endpoints.add(server.endpoint)) {
        throw const FormatException('duplicate Server endpoint');
      }
    }
    final selected = value['selectedEndpoint'] as String?;
    if (selected != null && !endpoints.contains(selected)) {
      throw const FormatException('selected Server missing');
    }
    _servers = List.unmodifiable(servers);
    _selectedEndpoint = selected;
  }

  static const Object _selectionUnchanged = Object();

  Future<void> _persist({
    List<HowlServerConnection>? servers,
    Object? selectedEndpoint = _selectionUnchanged,
  }) async {
    final next = servers ?? _servers;
    final selected = identical(selectedEndpoint, _selectionUnchanged)
        ? _selectedEndpoint
        : selectedEndpoint as String?;
    final encoded = jsonEncode(<String, Object?>{
      'schema': 'howl.server-connections/v1',
      'servers': next.map((server) => server.toJson()).toList(growable: false),
      'selectedEndpoint': selected,
    });
    if (utf8.encode(encoded).length > maximumEncodedBytes) {
      throw StateError('configuration too large');
    }
    await _store.write(encoded);
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('Server connections not initialized');
    if (_readFailed) {
      throw StateError('Retry reading saved Server connections before editing');
    }
  }

  static int _compareServers(
    HowlServerConnection left,
    HowlServerConnection right,
  ) {
    final label = left.label.toLowerCase().compareTo(right.label.toLowerCase());
    return label != 0 ? label : left.endpoint.compareTo(right.endpoint);
  }
}
