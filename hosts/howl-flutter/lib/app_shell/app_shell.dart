import 'dart:async';

import 'package:flutter/material.dart';

import '../server/endpoint.dart';
import '../server/attachment.dart';
import '../server/browser.dart';
import '../server/change.dart';
import '../server/connections.dart';
import '../server/launch.dart';
import '../server/tree.dart';

typedef HowlTerminalBuilder = Widget Function(
  BuildContext context,
  Attachment target,
  VoidCallback onStaleTarget,
  VoidCallback onBrowseSessions,
);

/// Minimal app shell around the terminal canary.
///
/// The shell owns saved Server endpoints and navigation only.
/// Sessions and Instances come from the fetched Server tree; an open terminal
/// is just one transient attachment to a Server-owned Instance.
final class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.terminalBuilder,
    this.initialServerEndpoint,
    this.initialAttachment,
    this.connections,
    this.fetchTree = NativeServerTree.request,
    this.launchTerminal = ServerLaunch.request,
    this.changeServer = ServerChange.request,
  });

  final HowlTerminalBuilder terminalBuilder;
  final Endpoint? initialServerEndpoint;
  final Attachment? initialAttachment;
  final ServerConnections? connections;
  final ServerTreeFetcher fetchTree;
  final ServerLauncher launchTerminal;
  final ServerChanger changeServer;

  @override
  State<AppShell> createState() => _AppShellState();
}

final class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ServerConnections _connections;
  late final bool _ownsConnections;
  Endpoint? _activeServer;
  Attachment? _attachment;
  bool _followSavedServer = false;
  bool _initialized = false;
  int _navigation = 0;

  @override
  void initState() {
    super.initState();
    _ownsConnections = widget.connections == null;
    _connections =
        widget.connections ??
        ServerConnections(SharedPreferencesServerConnectionStore());
    _connections.addListener(_connectionsChanged);
    _attachment = widget.initialAttachment;
    _activeServer = widget.initialServerEndpoint ?? _attachment?.serverEndpoint;
    _initialized = _activeServer != null || _attachment != null;
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
    if (_activeServer == null && _attachment == null) {
      final selected = _connections.selectedEndpoint;
      if (selected != null) {
        _activeServer = Endpoint.parse(selected);
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
      _activeServer = selected == null ? null : Endpoint.parse(selected);
      _attachment = null;
      if (selected == null) _followSavedServer = false;
    });
  }

  Future<bool> _selectServer(
    ServerConnection server, {
    bool closeCurrentRoute = true,
  }) async {
    final navigation = ++_navigation;
    try {
      await _connections.select(server.endpoint);
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
      return false;
    }
    if (!mounted ||
        navigation != _navigation ||
        _connections.selectedEndpoint != server.endpoint ||
        _connections.find(server.endpoint) == null) {
      return false;
    }
    final endpoint = Endpoint.parse(server.endpoint);
    setState(() {
      if (_activeServer?.toString() != endpoint.toString()) {
        _activeServer = endpoint;
        _attachment = null;
      }
      _followSavedServer = true;
    });
    if (closeCurrentRoute) _closeDrawer();
    return true;
  }

  void _openInstance(Attachment target) {
    _navigation++;
    setState(() {
      _activeServer = target.serverEndpoint;
      _attachment = target;
    });
    _closeDrawer();
  }

  void _browseSessions() => _openDrawer();

  void _staleTarget() {
    final target = _attachment;
    if (target == null) return;
    _navigation++;
    setState(() {
      _activeServer = target.serverEndpoint;
      _attachment = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDrawer();
    });
  }

  void _closedSession(String sessionId) {
    if (_attachment?.sessionId != sessionId) return;
    setState(() {
      _attachment = null;
    });
  }

  void _closedInstance(String sessionId, String instanceId) {
    if (_attachment?.sessionId != sessionId ||
        _attachment?.instanceId != instanceId) {
      return;
    }
    setState(() => _attachment = null);
  }

  void _openSettings() {
    _closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ServerSettingsPage(
          connections: _connections,
          activeServer: _activeServer,
          onSelectServer: _selectServer,
        ),
      ),
    );
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _closeDrawer() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Widget _buildBody(BuildContext context) {
    if (!_initialized) return const _ShellLoading();
    final instance = _attachment;
    if (instance != null) {
      return widget.terminalBuilder(
        context,
        instance,
        _staleTarget,
        _browseSessions,
      );
    }
    if (_activeServer != null) return _BrowsePrompt(onBrowse: _openDrawer);
    return _EmptyShell(onConfigure: _openSettings);
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: false,
      drawer: _SessionDrawer(
        connections: _connections,
        activeServer: _activeServer,
        fetchTree: widget.fetchTree,
        launchTerminal: widget.launchTerminal,
        changeServer: widget.changeServer,
        onSelectServer: (server) =>
            _selectServer(server, closeCurrentRoute: false),
        onOpenInstance: _openInstance,
        onClosedSession: _closedSession,
        onClosedInstance: _closedInstance,
        onSettings: _openSettings,
      ),
      body: _attachment != null
          ? body
          : Stack(
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

final class _BrowsePrompt extends StatelessWidget {
  const _BrowsePrompt({required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff090b0e),
    child: Center(
      child: FilledButton.icon(
        key: const Key('howl-open-sessions'),
        onPressed: onBrowse,
        icon: const Icon(Icons.folder_open),
        label: const Text('Open Sessions'),
      ),
    ),
  );
}

final class _SessionDrawer extends StatelessWidget {
  const _SessionDrawer({
    required this.connections,
    required this.activeServer,
    required this.fetchTree,
    required this.launchTerminal,
    required this.changeServer,
    required this.onSelectServer,
    required this.onOpenInstance,
    required this.onClosedSession,
    required this.onClosedInstance,
    required this.onSettings,
  });

  final ServerConnections connections;
  final Endpoint? activeServer;
  final ServerTreeFetcher fetchTree;
  final ServerLauncher launchTerminal;
  final ServerChanger changeServer;
  final Future<bool> Function(ServerConnection) onSelectServer;
  final ValueChanged<Attachment> onOpenInstance;
  final ValueChanged<String> onClosedSession;
  final void Function(String sessionId, String instanceId) onClosedInstance;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final servers = connections.servers.toList();
    final selected = activeServer?.toString();
    if (selected != null && connections.find(selected) == null) {
      servers.insert(
        0,
        ServerConnection(label: 'Current Server', endpoint: selected),
      );
    }
    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('Howl'),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('howl-server-picker'),
                  isExpanded: true,
                  value:
                      selected != null &&
                          servers.any((server) => server.endpoint == selected)
                      ? selected
                      : null,
                  hint: const Text('Choose Server'),
                  items: <DropdownMenuItem<String>>[
                    for (final server in servers)
                      DropdownMenuItem(
                        value: server.endpoint,
                        child: Text(
                          'Server: ${server.label}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (endpoint) {
                    final server = endpoint == null
                        ? null
                        : connections.find(endpoint);
                    if (server != null) onSelectServer(server);
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: activeServer == null
                  ? const Center(child: Text('Add a Server in Settings'))
                  : ServerBrowser(
                      key: ValueKey<String>('server-browser:$activeServer'),
                      endpoint: activeServer!,
                      availableServers: connections.servers.toList(),
                      onChooseServer: onSelectServer,
                      fetchTree: fetchTree,
                      launchTerminal: launchTerminal,
                      changeServer: changeServer,
                      onOpenInstance: onOpenInstance,
                      onClosedSession: onClosedSession,
                      onClosedInstance: onClosedInstance,
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('howl-shell-settings'),
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ServerSettingsPage extends StatelessWidget {
  const _ServerSettingsPage({
    required this.connections,
    required this.activeServer,
    required this.onSelectServer,
  });

  final ServerConnections connections;
  final Endpoint? activeServer;
  final Future<bool> Function(ServerConnection) onSelectServer;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: connections,
    builder: (context, _) {
      final servers = connections.servers;
      return Scaffold(
        appBar: AppBar(title: const Text('Server Settings')),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (connections.loadError != null)
                TextButton(
                  onPressed: () => connections.retryLoad(),
                  child: const Text('Retry loading saved Servers'),
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
    },
  );
}

enum _ServerAction { edit, remove }

Future<void> _editServer(
  BuildContext context,
  ServerConnections connections, {
  ServerConnection? existing,
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

  final ServerConnections connections;
  final ServerConnection? existing;

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
      final value = ServerConnection(
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
          EndpointException() => 'Invalid Howl endpoint',
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
  ServerConnections connections,
  ServerConnection server,
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
