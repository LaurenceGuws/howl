import 'dart:async';

import 'package:flutter/material.dart';

import 'endpoint.dart';
import 'attachment.dart';
import '../delete/native_host.dart';
import 'change.dart';
import 'connections.dart';
import 'launch.dart';
import 'tree.dart';

typedef ServerTreeFetcher = ServerTreeRequest Function(Endpoint endpoint);

/// One Session -> Instance explorer inside the app drawer.
///
/// Only expansion belongs to Flutter; the Server owns the tree and lifecycle.
final class ServerBrowser extends StatefulWidget {
  const ServerBrowser({
    super.key,
    required this.endpoint,
    required this.onOpenInstance,
    this.availableServers = const <ServerConnection>[],
    this.onChooseServer,
    this.onClosedSession,
    this.onClosedInstance,
    this.initialExpandedSessionId,
    this.fetchTree = NativeServerTree.request,
    this.launchTerminal = ServerLaunch.request,
    this.changeServer = ServerChange.request,
  });

  final Endpoint endpoint;
  final ValueChanged<Attachment> onOpenInstance;
  final List<ServerConnection> availableServers;
  final Future<bool> Function(ServerConnection)? onChooseServer;
  final ValueChanged<String>? onClosedSession;
  final void Function(String sessionId, String instanceId)? onClosedInstance;
  final String? initialExpandedSessionId;

  final ServerTreeFetcher fetchTree;
  final ServerLauncher launchTerminal;
  final ServerChanger changeServer;

  @override
  State<ServerBrowser> createState() => _ServerBrowserState();
}

final class _ServerBrowserState extends State<ServerBrowser>
    with WidgetsBindingObserver {
  static const Duration _treeDeadline = Duration(seconds: 18);
  static const Duration _launchDeadline = Duration(seconds: 23);

  ServerTree? _tree;
  Object? _failure;
  bool _loading = true;
  ServerTreeRequest? _request;
  ServerTreeRequest? _otherServerRequest;
  ServerLaunchRequest? _launchRequest;
  ServerChangeRequest? _changeRequest;
  bool _busy = false;
  String? _expandedSessionId;

  @override
  void initState() {
    super.initState();
    _expandedSessionId = widget.initialExpandedSessionId;
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_busy) {
      unawaited(_refresh());
    }
  }

  @override
  void didUpdateWidget(covariant ServerBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint.toString() != widget.endpoint.toString()) {
      _expandedSessionId = null;
      _tree = null;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final prior = _request;
    _request = null;
    if (prior != null) {
      try {
        prior.cancel();
      } catch (error) {
        if (mounted) {
          setState(() {
            _failure = error;
            _loading = false;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }
    ServerTreeRequest? request;
    try {
      request = widget.fetchTree(widget.endpoint);
      _request = request;
      final tree = await request.future.timeout(
        _treeDeadline,
        onTimeout: () {
          request!.cancel();
          throw const ServerTreeException(
            'server_tree_timeout',
            kind: NativeFailureKind.transport,
          );
        },
      );
      if (!mounted || !identical(_request, request)) return;
      setState(() {
        _tree = tree;
        _loading = false;
        if (_expandedSessionId != null &&
            !tree.sessions.any((s) => s.id == _expandedSessionId)) {
          _expandedSessionId = null;
        }
        if (_expandedSessionId == null && tree.sessions.length == 1) {
          _expandedSessionId = tree.sessions.single.id;
        }
      });
    } catch (error) {
      if (!mounted || (request != null && !identical(_request, request))) {
        return;
      }
      setState(() {
        _failure = error;
        _loading = false;
      });
    } finally {
      if (request != null && identical(_request, request)) _request = null;
    }
  }

  void _cancelTreeRequest() {
    final request = _request;
    _request = null;
    try {
      request?.cancel();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error;
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _failure = const ServerTreeException(
        'server_tree_canceled',
        kind: NativeFailureKind.canceled,
      );
      _loading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      _request?.cancel();
    } catch (_) {}
    _request = null;
    _otherServerRequest?.cancel();
    _launchRequest?.cancel();
    _changeRequest?.cancel();
    _launchRequest = null;
    super.dispose();
  }

  Future<void> _promptLaunch(ServerSession session) async {
    final tree = _tree;
    if (tree == null || _busy) return;
    final shell = await showDialog<String>(
      context: context,
      builder: (_) => _LaunchDialog(session: session),
    );
    if (shell == null || !mounted || _busy) return;
    if (shell.isEmpty || shell.contains('\u0000')) {
      _showFailure('Check shell path');
      return;
    }
    await _launch(tree, session, shell);
  }

  Future<void> _launch(
    ServerTree tree,
    ServerSession session,
    String shell,
  ) async {
    if (_busy) return;
    final ServerLaunchRequest request;
    try {
      request = widget.launchTerminal(
        widget.endpoint,
        tree.serverId,
        sessionId: session.id,
        shell: shell,
      );
    } catch (error) {
      _showFailure('Could not launch Instance: $error');
      return;
    }
    _launchRequest = request;
    setState(() => _busy = true);
    try {
      final receipt = await request.future.timeout(
        _launchDeadline,
        onTimeout: () {
          request.cancel();
          throw const ServerTreeException(
            'server_launch_timeout',
            kind: NativeFailureKind.transport,
          );
        },
      );
      if (!mounted || !identical(_launchRequest, request)) return;
      if (receipt.serverId != tree.serverId ||
          receipt.sessionId != session.id) {
        throw const ServerTreeException('launch_identity');
      }
      // The drawer can remain mounted behind the terminal. Reconcile its
      // Server-owned tree now so reopening it shows the new Instance.
      unawaited(_refresh());
      widget.onOpenInstance(
        Attachment(
          serverEndpoint: widget.endpoint,
          serverId: receipt.serverId,
          sessionId: receipt.sessionId,
          instanceId: receipt.instanceId,
        ),
      );
    } catch (error) {
      if (!mounted || !identical(_launchRequest, request)) return;
      _showFailure('Could not launch Instance: $error');
      await _refresh();
    } finally {
      if (mounted && identical(_launchRequest, request)) {
        setState(() {
          _launchRequest = null;
          _busy = false;
        });
      }
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<ServerConnection> get _servers {
    final servers = widget.availableServers.toList();
    if (!servers.any(
      (server) => server.endpoint == widget.endpoint.toString(),
    )) {
      servers.insert(
        0,
        ServerConnection(
          label: 'Current Server',
          endpoint: widget.endpoint.toString(),
        ),
      );
    }
    return servers;
  }

  Future<void> _newSession() async {
    final tree = _tree;
    if (tree == null || _busy) return;
    var name = 'mobile';
    var suffix = 2;
    while (tree.sessions.any((session) => session.name == name)) {
      name = 'mobile-${suffix++}';
    }
    final details = await showDialog<_NewSessionDetails>(
      context: context,
      builder: (_) => _NewSessionDialog(
        servers: _servers,
        initialEndpoint: widget.endpoint.toString(),
        suggestedName: name,
      ),
    );
    if (details == null || !mounted || _busy) return;
    if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(details.name)) {
      _showFailure('Check Session name');
      return;
    }
    if (details.endpoint != widget.endpoint.toString() &&
        widget.onChooseServer == null) {
      _showFailure('Cannot switch to the selected Server');
      return;
    }
    setState(() => _busy = true);
    try {
      final endpoint = Endpoint.parse(details.endpoint);
      var targetTree = tree;
      if (endpoint.toString() != widget.endpoint.toString()) {
        final request = widget.fetchTree(endpoint);
        _otherServerRequest = request;
        try {
          targetTree = await request.future.timeout(
            _treeDeadline,
            onTimeout: () {
              request.cancel();
              throw const ServerTreeException(
                'server_tree_timeout',
                kind: NativeFailureKind.transport,
              );
            },
          );
        } finally {
          if (identical(_otherServerRequest, request)) {
            _otherServerRequest = null;
          }
        }
      }
      if (!mounted) return;
      final change = widget.changeServer(
        endpoint,
        targetTree.serverId,
        kind: ServerChangeKind.createSession,
        name: details.name,
      );
      _changeRequest = change;
      final receipt = await change.future.timeout(
        _launchDeadline,
        onTimeout: () {
          change.cancel();
          throw const ServerTreeException(
            'server_change_timeout',
            kind: NativeFailureKind.transport,
          );
        },
      );
      if (!mounted || !identical(_changeRequest, change)) return;
      if (receipt.serverId != targetTree.serverId) {
        throw const ServerTreeException('change_server_identity');
      }
      _changeRequest = null;
      if (endpoint.toString() == widget.endpoint.toString()) {
        _expandedSessionId = receipt.sessionId;
        await _refresh();
      } else {
        final selected = _servers.firstWhere(
          (server) => server.endpoint == endpoint.toString(),
        );
        final switched = await widget.onChooseServer!(selected);
        if (!switched && mounted) {
          _showFailure(
            'Session created on ${selected.label}, but Server selection failed',
          );
        }
      }
    } catch (error) {
      if (mounted) _showFailure('Could not create Session: $error');
    } finally {
      _changeRequest = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClose(
    ServerSession session, [
    ServerInstance? instance,
  ]) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          instance == null
              ? 'Close Session "${session.name}"?'
              : 'Close Instance ${instance.id}?',
        ),
        content: Text(
          instance == null
              ? 'This closes all ${session.instances.length} Instances and their processes on the Server.'
              : 'The Server will stop this Instance and its process.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(instance == null ? 'Close Session' : 'Close Instance'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy || _tree == null) return;
    final tree = _tree!;
    setState(() => _busy = true);
    try {
      final change = widget.changeServer(
        widget.endpoint,
        tree.serverId,
        kind: instance == null
            ? ServerChangeKind.closeSession
            : ServerChangeKind.closeInstance,
        sessionId: session.id,
        instanceId: instance?.id,
      );
      _changeRequest = change;
      final receipt = await change.future.timeout(
        _launchDeadline,
        onTimeout: () {
          change.cancel();
          throw const ServerTreeException(
            'server_change_timeout',
            kind: NativeFailureKind.transport,
          );
        },
      );
      if (!mounted || !identical(_changeRequest, change)) return;
      if (receipt.serverId != tree.serverId ||
          receipt.sessionId != session.id) {
        throw const ServerTreeException('change_identity');
      }
      if (instance == null) {
        widget.onClosedSession?.call(session.id);
      } else {
        widget.onClosedInstance?.call(session.id, instance.id);
      }
      await _refresh();
    } catch (error) {
      if (mounted) _showFailure('Could not close: $error');
    } finally {
      _changeRequest = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(String serverId, ServerSession session, ServerInstance instance) {
    if (_busy || instance.state != ServerInstanceState.running) return;
    final target = Attachment(
      serverEndpoint: widget.endpoint,
      serverId: serverId,
      sessionId: session.id,
      instanceId: instance.id,
    );
    widget.onOpenInstance(target);
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    return Material(
      color: const Color(0xff090b0e),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text('Sessions', style: TextStyle(fontSize: 18)),
                ),
                if (_busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  key: const Key('howl-new-session'),
                  tooltip: 'New Session',
                  onPressed: tree == null || _busy ? null : _newSession,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading || _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: _failure != null
                ? _message('Server unavailable', '$_failure', 'Retry', _refresh)
                : tree == null
                ? _message(
                    'Connecting to Server',
                    widget.endpoint.toString(),
                    'Cancel',
                    _cancelTreeRequest,
                  )
                : tree.sessions.isEmpty
                ? const Center(child: Text('No Sessions yet'))
                : ListView(
                    children: <Widget>[
                      for (final session in tree.sessions)
                        _sessionRow(tree, session),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _message(
    String title,
    String details,
    String action,
    VoidCallback callback,
  ) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title),
          const SizedBox(height: 8),
          Text(details, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: callback, child: Text(action)),
        ],
      ),
    ),
  );

  Widget _sessionRow(ServerTree tree, ServerSession session) {
    final expanded = session.id == _expandedSessionId;
    return Column(
      children: <Widget>[
        ListTile(
          key: Key('howl-session-${session.id}'),
          dense: true,
          leading: Icon(expanded ? Icons.folder_open : Icons.folder_outlined),
          title: Text(session.name),
          subtitle: Text('${session.instances.length} Instances'),
          onTap: () =>
              setState(() => _expandedSessionId = expanded ? null : session.id),
          trailing: PopupMenuButton<_SessionAction>(
            tooltip: 'Session options',
            enabled: !_busy,
            onSelected: (action) {
              switch (action) {
                case _SessionAction.newInstance:
                  _promptLaunch(session);
                case _SessionAction.close:
                  _confirmClose(session);
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<_SessionAction>>[
              PopupMenuItem(
                value: _SessionAction.newInstance,
                child: Text('New Instance'),
              ),
              PopupMenuItem(
                value: _SessionAction.close,
                child: Text('Close Session'),
              ),
            ],
          ),
        ),
        if (expanded) ...<Widget>[
          for (final instance in session.instances)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: ListTile(
                key: Key('howl-instance-${session.id}-${instance.id}'),
                dense: true,
                leading: Icon(
                  instance.state == ServerInstanceState.running
                      ? Icons.circle
                      : Icons.stop_circle_outlined,
                  color: instance.state == ServerInstanceState.running
                      ? Colors.greenAccent
                      : Colors.grey,
                  size: 12,
                ),
                title: Text('Instance ${instance.id}'),
                subtitle: Text(instance.state.name),
                onTap: instance.state == ServerInstanceState.running && !_busy
                    ? () => _open(tree.serverId, session, instance)
                    : null,
                trailing: PopupMenuButton<_InstanceAction>(
                  tooltip: 'Instance options',
                  enabled: !_busy,
                  onSelected: (_) => _confirmClose(session, instance),
                  itemBuilder: (_) => const <PopupMenuEntry<_InstanceAction>>[
                    PopupMenuItem(
                      value: _InstanceAction.close,
                      child: Text('Close Instance'),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('howl-new-instance-${session.id}'),
                onPressed: _busy ? null : () => _promptLaunch(session),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('New Instance'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _SessionAction { newInstance, close }

enum _InstanceAction { close }

final class _NewSessionDetails {
  const _NewSessionDetails(this.endpoint, this.name);
  final String endpoint;
  final String name;
}

final class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({
    required this.servers,
    required this.initialEndpoint,
    required this.suggestedName,
  });
  final List<ServerConnection> servers;
  final String initialEndpoint;
  final String suggestedName;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

final class _NewSessionDialogState extends State<_NewSessionDialog> {
  late final TextEditingController _name;
  late String _endpoint;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.suggestedName);
    _endpoint = widget.initialEndpoint;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context)
          .pop(_NewSessionDetails(_endpoint, _name.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New Session'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            key: const Key('howl-new-session-server'),
            initialValue: _endpoint,
            decoration: const InputDecoration(labelText: 'Server'),
            isExpanded: true,
            items: <DropdownMenuItem<String>>[
              for (final server in widget.servers)
                DropdownMenuItem(
                  value: server.endpoint,
                  child: Text(server.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _endpoint = value);
            },
          ),
          TextField(
            key: const Key('howl-session-name'),
            controller: _name,
            autofocus: true,
            maxLength: 64,
            decoration: const InputDecoration(
              labelText: 'Session name',
              helperText: 'Letters, digits, dot, dash or underscore',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}

final class _LaunchDialog extends StatefulWidget {
  const _LaunchDialog({required this.session});
  final ServerSession session;

  @override
  State<_LaunchDialog> createState() => _LaunchDialogState();
}

final class _LaunchDialogState extends State<_LaunchDialog> {
  final TextEditingController _shell = TextEditingController(text: '/bin/bash');

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_shell.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New Instance'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('In ${widget.session.name}'),
        TextField(
          key: const Key('howl-instance-shell'),
          controller: _shell,
          decoration: const InputDecoration(labelText: 'Shell on Server'),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Launch')),
    ],
  );
}
