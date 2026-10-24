import 'dart:async';

import 'package:flutter/material.dart';

import 'howl_endpoint.dart';
import 'instance_target.dart';
import 'server_launch.dart';
import 'server_tree.dart';

typedef HowlServerTreeFetcher = HowlServerTreeRequest Function(
  HowlEndpoint endpoint,
);

/// Thin app-side browser over Server lifecycle identity.
///
/// This widget owns presentation only. It does not mirror Server state beyond one
/// fetched tree and does not interpret terminal geometry or layout.
final class HowlServerBrowser extends StatefulWidget {
  const HowlServerBrowser({
    super.key,
    required this.endpoint,
    required this.onOpenTarget,
    this.fetchTree = NativeServerTree.request,
    this.launchTerminal = NativeServerLaunch.request,
  });

  final HowlEndpoint endpoint;
  final ValueChanged<ManagedHowlInstanceTarget> onOpenTarget;

  final HowlServerTreeFetcher fetchTree;
  final HowlServerLauncher launchTerminal;

  @override
  State<HowlServerBrowser> createState() => _HowlServerBrowserState();
}

final class _HowlServerBrowserState extends State<HowlServerBrowser>
    with WidgetsBindingObserver {
  HowlServerTree? _tree;
  Object? _failure;
  bool _loading = true;
  HowlServerTreeRequest? _request;
  HowlServerLaunchRequest? _launchRequest;
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_launching) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final prior = _request;
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
    final request = widget.fetchTree(widget.endpoint);
    _request = request;
    try {
      final tree = await request.future;
      if (!mounted || !identical(_request, request)) return;
      setState(() {
        _tree = tree;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !identical(_request, request)) return;
      setState(() {
        _failure = error;
        _loading = false;
      });
    } finally {
      if (identical(_request, request)) _request = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      _request?.cancel();
    } catch (_) {}
    _request = null;
    _launchRequest?.cancel();
    _launchRequest = null;
    super.dispose();
  }

  Future<void> _promptLaunch([HowlServerSession? session]) async {
    final tree = _tree;
    if (tree == null || _launching) return;
    var suggestedName = 'mobile';
    var suffix = 2;
    while (tree.sessions.any((existing) => existing.name == suggestedName)) {
      suggestedName = 'mobile-${suffix++}';
    }
    final details = await showDialog<_LaunchDetails>(
      context: context,
      builder: (context) =>
          _LaunchDialog(session: session, suggestedName: suggestedName),
    );
    if (details == null || !mounted || _launching) return;
    if ((session == null &&
            !RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(details.name)) ||
        details.shell.isEmpty ||
        details.shell.contains('\u0000')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check Session name and shell path')),
      );
      return;
    }
    await _launch(
      tree,
      sessionId: session?.id,
      sessionName: session == null ? details.name : null,
      shell: details.shell,
    );
  }

  Future<void> _launch(
    HowlServerTree tree, {
    String? sessionId,
    String? sessionName,
    required String shell,
  }) async {
    if (_launching) return;
    final HowlServerLaunchRequest request;
    try {
      request = widget.launchTerminal(
        widget.endpoint,
        tree.serverId,
        sessionId: sessionId,
        sessionName: sessionName,
        shell: shell,
      );
    } catch (error) {
      _showLaunchFailure(error);
      return;
    }
    _launchRequest = request;
    setState(() => _launching = true);
    try {
      final receipt = await request.future;
      if (!mounted || !identical(_launchRequest, request)) return;
      if (receipt.serverId != tree.serverId) {
        throw const HowlServerTreeException('launch_server_identity');
      }
      widget.onOpenTarget(
        ManagedHowlInstanceTarget(
          serverEndpoint: widget.endpoint,
          serverId: receipt.serverId,
          sessionId: receipt.sessionId,
          instanceId: receipt.instanceId,
        ),
      );
    } catch (error) {
      if (!mounted || !identical(_launchRequest, request)) return;
      _showLaunchFailure(error);
      await _refresh();
    } finally {
      if (mounted && identical(_launchRequest, request)) {
        setState(() {
          _launchRequest = null;
          _launching = false;
        });
      }
    }
  }

  void _showLaunchFailure(Object failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not launch terminal: $failure')),
    );
  }

  void _open(
    String serverId,
    HowlServerSession session,
    HowlServerInstance instance,
  ) {
    if (instance.state != HowlServerInstanceState.running) return;
    final target = ManagedHowlInstanceTarget(
      serverEndpoint: widget.endpoint,
      serverId: serverId,
      sessionId: session.id,
      instanceId: instance.id,
    );
    widget.onOpenTarget(target);
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final tree = _tree;
    return Scaffold(
      backgroundColor: const Color(0xff090b0e),
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        leadingWidth: 48,
        title: const Text('Howl Server'),
        toolbarHeight: 44,
        actions: <Widget>[
          if (_launching)
            const Center(child: Text('Launching...'))
          else
            IconButton(
              tooltip: 'New Session + terminal',
              onPressed: tree == null ? null : () => _promptLaunch(),
              icon: const Icon(Icons.add),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: failure != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Server unavailable'),
                    const SizedBox(height: 8),
                    Text(
                      '$failure',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : tree == null
          ? const Center(child: CircularProgressIndicator())
          : _buildTree(context, tree),
    );
  }

  Widget _buildTree(BuildContext context, HowlServerTree tree) {
    if (tree.sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('No Sessions yet'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _launching ? null : () => _promptLaunch(),
              icon: const Icon(Icons.add),
              label: const Text('Create first terminal'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tree.sessions.length,
        itemBuilder: (context, index) {
          final session = tree.sessions[index];
          return _SessionSection(
            session: session,
            onNewTerminal: _launching ? null : () => _promptLaunch(session),
            onOpen: (session, instance) =>
                _open(tree.serverId, session, instance),
          );
        },
      ),
    );
  }
}

final class _SessionSection extends StatelessWidget {
  const _SessionSection({
    required this.session,
    required this.onOpen,
    required this.onNewTerminal,
  });

  final HowlServerSession session;
  final VoidCallback? onNewTerminal;
  final void Function(HowlServerSession, HowlServerInstance) onOpen;

  @override
  Widget build(BuildContext context) {
    final instances = session.instances;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      session.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'New terminal in ${session.name}',
                    onPressed: onNewTerminal,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            if (instances.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text('No Instances'),
              )
            else
              for (final instance in instances)
                ListTile(
                  dense: true,
                  title: Text('Instance ${instance.id}'),
                  subtitle: Text(instance.state.name),
                  enabled: instance.state == HowlServerInstanceState.running,
                  trailing: instance.state == HowlServerInstanceState.running
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: instance.state == HowlServerInstanceState.running
                      ? () => onOpen(session, instance)
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

final class _LaunchDetails {
  const _LaunchDetails(this.name, this.shell);
  final String name;
  final String shell;
}

/// Owns its text controllers until the dialog route actually retires.
final class _LaunchDialog extends StatefulWidget {
  const _LaunchDialog({required this.session, required this.suggestedName});

  final HowlServerSession? session;
  final String suggestedName;

  @override
  State<_LaunchDialog> createState() => _LaunchDialogState();
}

final class _LaunchDialogState extends State<_LaunchDialog> {
  late final TextEditingController _name;
  final TextEditingController _shell = TextEditingController(text: '/bin/sh');

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.suggestedName);
  }

  @override
  void dispose() {
    _name.dispose();
    _shell.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
    context,
    _LaunchDetails(_name.text.trim(), _shell.text.trim()),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.session == null ? 'New Session + terminal' : 'New terminal',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.session == null) ...<Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Session name',
                helperText: 'Letters, digits, dot, dash or underscore',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
          ] else
            Text('In ${widget.session!.name}'),
          TextField(
            controller: _shell,
            decoration: const InputDecoration(labelText: 'Shell on Server'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Launch')),
    ],
  );
}
