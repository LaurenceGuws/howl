import 'dart:async';

import 'package:flutter/material.dart';

import 'howl_endpoint.dart';
import 'instance_target.dart';
import 'server_browser.dart';
import 'server_connections.dart';
import 'server_tree.dart';

typedef HowlTerminalBuilder = Widget Function(
  BuildContext context,
  HowlInstanceTarget target,
);

/// Minimal app shell around the terminal canary.
///
/// The shell owns saved Server endpoints and app navigation only. It deliberately
/// owns no Server mirror, terminal grid, Session lifecycle, pane layout, or transport.
final class HowlAppShell extends StatefulWidget {
  const HowlAppShell({
    super.key,
    required this.terminalBuilder,
    this.initialServerEndpoint,
    this.initialInstanceTarget,
    this.connections,
    this.fetchTree = NativeServerTree.fetch,
  });

  final HowlTerminalBuilder terminalBuilder;
  final HowlEndpoint? initialServerEndpoint;
  final HowlInstanceTarget? initialInstanceTarget;
  final HowlServerConnections? connections;
  final HowlServerTreeFetcher fetchTree;

  @override
  State<HowlAppShell> createState() => _HowlAppShellState();
}

final class _HowlAppShellState extends State<HowlAppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final HowlServerConnections _connections;
  late final bool _ownsConnections;
  HowlEndpoint? _activeServer;
  HowlInstanceTarget? _activeInstance;
  bool _followSavedServer = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ownsConnections = widget.connections == null;
    _connections =
        widget.connections ??
        HowlServerConnections(SharedPreferencesHowlServerConnectionStore());
    _connections.addListener(_connectionsChanged);
    _activeInstance = widget.initialInstanceTarget;
    _activeServer =
        widget.initialServerEndpoint ??
        switch (_activeInstance) {
          ManagedHowlInstanceTarget target => target.serverEndpoint,
          _ => null,
        };
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _connections.removeListener(_connectionsChanged);
    if (_ownsConnections) _connections.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _connections.initialize();
    if (!mounted) return;
    if (_activeServer == null && _activeInstance == null) {
      final selected = _connections.selectedEndpoint;
      if (selected != null) {
        _activeServer = HowlEndpoint.parse(selected);
        _followSavedServer = true;
      }
    }
    setState(() => _initialized = true);
  }

  void _connectionsChanged() {
    if (!mounted) return;
    if (!_followSavedServer) {
      setState(() {});
      return;
    }

    final selected = _connections.selectedEndpoint;
    final current = _activeServer?.toString();
    if (selected == current) {
      setState(() {});
      return;
    }

    setState(() {
      _activeServer = selected == null ? null : HowlEndpoint.parse(selected);
      _activeInstance = null;
      if (selected == null) _followSavedServer = false;
    });
  }

  Future<void> _selectServer(HowlServerConnection server) async {
    final endpoint = HowlEndpoint.parse(server.endpoint);
    await _connections.select(server.endpoint);
    if (!mounted) return;
    setState(() {
      _activeServer = endpoint;
      _activeInstance = null;
      _followSavedServer = true;
    });
    _closeDrawer();
  }

  void _openManaged(ManagedHowlInstanceTarget target) {
    setState(() {
      _activeServer = target.serverEndpoint;
      _activeInstance = target;
    });
  }

  void _backToServer() {
    if (_activeServer == null) return;
    setState(() => _activeInstance = null);
    _closeDrawer();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _closeDrawer() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Widget _buildBody(BuildContext context) {
    if (!_initialized) return const _ShellLoading();
    final instance = _activeInstance;
    if (instance != null) return widget.terminalBuilder(context, instance);
    final server = _activeServer;
    if (server != null) {
      return HowlServerBrowser(
        key: ValueKey<String>('server:${server.toString()}'),
        endpoint: server,
        fetchTree: widget.fetchTree,
        onOpenTarget: _openManaged,
      );
    }
    return _EmptyShell(onConfigure: _openDrawer);
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: false,
      drawer: _ServerDrawer(
        connections: _connections,
        activeServer: _activeServer,
        activeInstance: _activeInstance,
        onSelectServer: _selectServer,
        onBackToServer: _backToServer,
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          Positioned(
            left: 6,
            top: MediaQuery.paddingOf(context).top + 6,
            child: _ShellMenuButton(onPressed: _openDrawer),
          ),
        ],
      ),
    );
  }
}

final class _ShellMenuButton extends StatelessWidget {
  const _ShellMenuButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xcc15181c),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0x552f353c)),
    ),
    child: SizedBox.square(
      dimension: 36,
      child: IconButton(
        key: const Key('howl-shell-menu'),
        tooltip: 'Howl menu',
        padding: EdgeInsets.zero,
        iconSize: 19,
        onPressed: onPressed,
        icon: const Icon(Icons.menu),
      ),
    ),
  );
}

final class _ShellLoading extends StatelessWidget {
  const _ShellLoading();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xff090b0e),
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

final class _EmptyShell extends StatelessWidget {
  const _EmptyShell({required this.onConfigure});
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff090b0e),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.terminal, size: 30),
            const SizedBox(height: 12),
            Text(
              'No Server configured',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Add a Howl Server endpoint to browse its Sessions and Instances.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('howl-shell-configure'),
              onPressed: onConfigure,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Server'),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _ServerDrawer extends StatelessWidget {
  const _ServerDrawer({
    required this.connections,
    required this.activeServer,
    required this.activeInstance,
    required this.onSelectServer,
    required this.onBackToServer,
  });

  final HowlServerConnections connections;
  final HowlEndpoint? activeServer;
  final HowlInstanceTarget? activeInstance;
  final Future<void> Function(HowlServerConnection) onSelectServer;
  final VoidCallback onBackToServer;

  @override
  Widget build(BuildContext context) {
    final servers = connections.servers;
    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.terminal, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Howl',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 19),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (activeInstance
                case final ManagedHowlInstanceTarget target?) ...<Widget>[
              ListTile(
                key: const Key('howl-shell-back-server'),
                dense: true,
                leading: const Icon(Icons.arrow_back, size: 19),
                title: const Text('Back to Server'),
                subtitle: Text(
                  'Session ${target.sessionId} · Instance ${target.instanceId}',
                ),
                onTap: onBackToServer,
              ),
              const Divider(height: 1),
            ] else if (activeInstance
                case final DirectHowlInstanceTarget target?) ...<Widget>[
              ListTile(
                dense: true,
                leading: const Icon(Icons.bolt, size: 19),
                title: const Text('Direct Instance'),
                subtitle: Text(
                  target.endpointText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Connections',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('howl-shell-add-server'),
                    tooltip: 'Add Server',
                    onPressed: () => _editServer(context, connections),
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ],
              ),
            ),
            if (connections.loadError case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: servers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No saved Servers',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: servers.length,
                      itemBuilder: (context, index) {
                        final server = servers[index];
                        final selected =
                            activeServer?.toString() == server.endpoint;
                        return ListTile(
                          key: Key('howl-shell-server-${server.endpoint}'),
                          dense: true,
                          selected: selected,
                          leading: Icon(
                            selected ? Icons.dns : Icons.dns_outlined,
                            size: 19,
                          ),
                          title: Text(server.label),
                          subtitle: Text(
                            server.endpoint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => onSelectServer(server),
                          trailing: PopupMenuButton<_ServerAction>(
                            tooltip: 'Server options',
                            onSelected: (action) {
                              switch (action) {
                                case _ServerAction.edit:
                                  _editServer(
                                    context,
                                    connections,
                                    existing: server,
                                  );
                                case _ServerAction.remove:
                                  _removeServer(context, connections, server);
                              }
                            },
                            itemBuilder: (context) =>
                                const <PopupMenuEntry<_ServerAction>>[
                                  PopupMenuItem(
                                    value: _ServerAction.edit,
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: _ServerAction.remove,
                                    child: Text('Remove'),
                                  ),
                                ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ServerAction { edit, remove }

Future<void> _editServer(
  BuildContext context,
  HowlServerConnections connections, {
  HowlServerConnection? existing,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _ServerEditorDialog(connections: connections, existing: existing),
  );
}

final class _ServerEditorDialog extends StatefulWidget {
  const _ServerEditorDialog({
    required this.connections,
    required this.existing,
  });

  final HowlServerConnections connections;
  final HowlServerConnection? existing;

  @override
  State<_ServerEditorDialog> createState() => _ServerEditorDialogState();
}

final class _ServerEditorDialogState extends State<_ServerEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _endpoint;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.existing?.label ?? '');
    _endpoint = TextEditingController(
      text: widget.existing?.endpoint ?? 'tcp://',
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final value = HowlServerConnection(
        label: _label.text,
        endpoint: _endpoint.text.trim(),
      );
      await widget.connections.upsert(
        value,
        replacingEndpoint: widget.existing?.endpoint,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (failure) {
          HowlEndpointException() => 'Invalid Howl endpoint',
          ArgumentError() => 'Name is required',
          StateError() => '$failure',
          _ => 'Could not save Server',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Add Server' : 'Edit Server'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('howl-server-label'),
              controller: _label,
              autofocus: true,
              maxLength: 80,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              key: const Key('howl-server-endpoint'),
              controller: _endpoint,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                hintText: 'tcp://192.168.1.20:43130',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('howl-server-save'),
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}

Future<void> _removeServer(
  BuildContext context,
  HowlServerConnections connections,
  HowlServerConnection server,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove Server?'),
      content: Text('${server.label}\n${server.endpoint}'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('howl-server-remove-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed == true) await connections.remove(server.endpoint);
}
