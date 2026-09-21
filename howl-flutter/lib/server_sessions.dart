import 'dart:convert';

enum HowlServerSessionState { running, exited, failed }

final class HowlServerSession {
  const HowlServerSession({
    required this.sessionId,
    required this.createdSequence,
    required this.state,
    required this.name,
    this.failure,
  });

  final int sessionId;
  final int createdSequence;
  final HowlServerSessionState state;
  final String name;
  final String? failure;

  bool get attachable => state != HowlServerSessionState.failed;
}

final class HowlServerRoster {
  const HowlServerRoster({
    required this.serverId,
    required this.rosterRevision,
    required this.capacity,
    required this.stopping,
    required this.sessions,
  });

  final String serverId;
  final int rosterRevision;
  final int capacity;
  final bool stopping;
  final List<HowlServerSession> sessions;

  HowlServerSession? byId(int sessionId) {
    for (final session in sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }

  HowlServerSession? byName(String name) {
    for (final session in sessions) {
      if (session.name == name) return session;
    }
    return null;
  }
}

final class HowlServerRosterException implements Exception {
  const HowlServerRosterException(this.code);

  final String code;

  @override
  String toString() => 'HowlServerRosterException($code)';
}

HowlServerRoster parseHowlServerRoster(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const HowlServerRosterException('json');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['schema'] != 'howl.flutter.server/v1') {
    throw const HowlServerRosterException('schema');
  }

  final serverId = decoded['server_id'];
  final revisionText = decoded['roster_revision'];
  final capacity = decoded['capacity'];
  final stopping = decoded['stopping'];
  final rows = decoded['sessions'];
  if (serverId is! String ||
      serverId.isEmpty ||
      revisionText is! String ||
      capacity is! int ||
      capacity <= 0 ||
      stopping is! bool ||
      rows is! List<Object?>) {
    throw const HowlServerRosterException('header');
  }
  final revision = int.tryParse(revisionText);
  if (revision == null || revision <= 0 || rows.length > capacity) {
    throw const HowlServerRosterException('header');
  }

  final sessions = <HowlServerSession>[];
  final ids = <int>{};
  final names = <String>{};
  var previousSequence = 0;
  for (final row in rows) {
    if (row is! Map<String, Object?>) {
      throw const HowlServerRosterException('session');
    }
    final idText = row['session_id'];
    final sequenceText = row['created_sequence'];
    final stateText = row['state'];
    final name = row['name'];
    final failure = row['failure'];
    if (idText is! String ||
        sequenceText is! String ||
        stateText is! String ||
        name is! String ||
        name.isEmpty ||
        (failure != null && failure is! String)) {
      throw const HowlServerRosterException('session');
    }
    final id = int.tryParse(idText);
    final sequence = int.tryParse(sequenceText);
    final state = switch (stateText) {
      'running' => HowlServerSessionState.running,
      'exited' => HowlServerSessionState.exited,
      'failed' => HowlServerSessionState.failed,
      _ => null,
    };
    if (id == null ||
        id <= 0 ||
        sequence == null ||
        sequence <= previousSequence ||
        state == null ||
        !ids.add(id) ||
        !names.add(name)) {
      throw const HowlServerRosterException('session');
    }
    if ((state == HowlServerSessionState.failed) !=
        (failure is String && failure.isNotEmpty)) {
      throw const HowlServerRosterException('failure');
    }
    previousSequence = sequence;
    sessions.add(
      HowlServerSession(
        sessionId: id,
        createdSequence: sequence,
        state: state,
        name: name,
        failure: failure as String?,
      ),
    );
  }

  return HowlServerRoster(
    serverId: serverId,
    rosterRevision: revision,
    capacity: capacity,
    stopping: stopping,
    sessions: List<HowlServerSession>.unmodifiable(sessions),
  );
}
