import 'package:flutter/material.dart';

import 'howl_endpoint.dart';
import 'instance_target.dart';
import 'server_tree.dart';

typedef HowlServerTreeFetcher = Future<HowlServerTree> Function(
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
    this.fetchTree = NativeServerTree.fetch,
  });

  final HowlEndpoint endpoint;
  final ValueChanged<ManagedHowlInstanceTarget> onOpenTarget;
  final HowlServerTreeFetcher fetchTree;

  @override
  State<HowlServerBrowser> createState() => _HowlServerBrowserState();
}

final class _HowlServerBrowserState extends State<HowlServerBrowser> {
  HowlServerTree? _tree;
  Object? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }
    try {
      final tree = await widget.fetchTree(widget.endpoint);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error;
        _loading = false;
      });
    }
  }

  void _open(HowlServerSession session, HowlServerInstance instance) {
    if (instance.state != HowlServerInstanceState.running) return;
    final target = ManagedHowlInstanceTarget(
      serverEndpoint: widget.endpoint,
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
      return const Center(child: Text('No Sessions'));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tree.sessions.length,
        itemBuilder: (context, index) {
          final session = tree.sessions[index];
          return _SessionSection(session: session, onOpen: _open);
        },
      ),
    );
  }
}

final class _SessionSection extends StatelessWidget {
  const _SessionSection({required this.session, required this.onOpen});

  final HowlServerSession session;
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
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Text(
                session.name,
                style: Theme.of(context).textTheme.titleSmall,
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
