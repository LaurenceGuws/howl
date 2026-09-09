import 'dart:async';

import 'package:flutter/material.dart';

import 'terminal_selection.dart';

/// Native-feeling selection chrome over a terminal-owned stable cell range.
///
/// Flutter supplies Material handles and the adaptive floating toolbar. Terminal
/// selection coordinates, text extraction, scrollback, and VT semantics remain
/// outside this widget.
final class TerminalSelectionChrome extends StatefulWidget {
  const TerminalSelectionChrome({
    super.key,
    required this.viewport,
    required this.range,
    required this.geometry,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onAutoScrollRows,
    required this.onCopy,
    required this.onPaste,
  });

  final TerminalSelectionViewport viewport;
  final TerminalSelectionRange range;
  final TerminalSelectionGeometry geometry;
  final ValueChanged<TerminalSelectionPoint> onStartChanged;
  final ValueChanged<TerminalSelectionPoint> onEndChanged;
  final ValueChanged<int> onAutoScrollRows;
  final VoidCallback onCopy;
  final VoidCallback onPaste;

  @override
  State<TerminalSelectionChrome> createState() =>
      _TerminalSelectionChromeState();
}

final class _TerminalSelectionChromeState
    extends State<TerminalSelectionChrome> {
  final LayerLink _toolbarLink = LayerLink();
  final LayerLink _startLink = LayerLink();
  final LayerLink _endLink = LayerLink();
  final ValueNotifier<bool> _startVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _endVisible = ValueNotifier<bool>(true);

  SelectionOverlay? _overlay;
  Offset? _startDragGlobal;
  Offset? _endDragGlobal;
  Timer? _autoScrollTimer;
  int _autoScrollRows = 0;
  bool _toolbarDesired = true;

  static const Duration _autoScrollInterval = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _scheduleOverlayUpdate(show: true);
  }

  @override
  void didUpdateWidget(TerminalSelectionChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleOverlayUpdate(show: false);
    _scheduleDraggingEndpointRefresh();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _overlay?.dispose();
    _startVisible.dispose();
    _endVisible.dispose();
    super.dispose();
  }

  _SelectionChromeGeometry? get _chromeGeometry {
    final ordered = widget.range.ordered;
    final startRow = widget.viewport.viewportRowFor(ordered.start);
    final endRow = widget.viewport.viewportRowFor(ordered.end);
    final startHandleRow =
        startRow ?? widget.viewport.viewportEdgeRowFor(ordered.start);
    final endHandleRow =
        endRow ?? widget.viewport.viewportEdgeRowFor(ordered.end);
    final start = startHandleRow == null
        ? null
        : widget.geometry.handlePoint(
            row: startHandleRow,
            column: ordered.start.column,
            end: false,
          );
    final end = endHandleRow == null
        ? null
        : widget.geometry.handlePoint(
            row: endHandleRow,
            column: ordered.end.column,
            end: true,
          );
    if (widget.geometry.terminalRect == null) return null;
    return _SelectionChromeGeometry(
      start: start,
      end: end,
      startVisible: startRow != null,
      endVisible: endRow != null,
      lineHeight: widget.geometry.rowHeight * widget.geometry.scale!,
    );
  }

  void _scheduleOverlayUpdate({required bool show}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final metrics = _chromeGeometry;
      if (metrics == null) {
        _overlay?.hide();
        return;
      }
      _startVisible.value = metrics.startVisible;
      _endVisible.value = metrics.endVisible;
      final endpoints = _selectionEndpoints(metrics);
      if (endpoints == null) {
        _overlay?.hide();
        return;
      }
      var overlay = _overlay;
      if (overlay == null) {
        overlay = SelectionOverlay(
          context: context,
          debugRequiredFor: widget,
          startHandleType: TextSelectionHandleType.left,
          lineHeightAtStart: metrics.lineHeight,
          onStartHandleDragStart: _onStartDragStart,
          onStartHandleDragUpdate: _onStartDragUpdate,
          onStartHandleDragEnd: _onStartDragEnd,
          endHandleType: TextSelectionHandleType.right,
          lineHeightAtEnd: metrics.lineHeight,
          onEndHandleDragStart: _onEndDragStart,
          onEndHandleDragUpdate: _onEndDragUpdate,
          onEndHandleDragEnd: _onEndDragEnd,
          selectionEndpoints: endpoints,
          selectionControls: materialTextSelectionHandleControls,
          selectionDelegate: null,
          clipboardStatus: null,
          startHandleLayerLink: _startLink,
          endHandleLayerLink: _endLink,
          toolbarLayerLink: _toolbarLink,
          startHandlesVisible: _startVisible,
          endHandlesVisible: _endVisible,
        );
        _overlay = overlay;
        overlay.showHandles();
        _showToolbarIfDesired(overlay);
        return;
      }
      overlay
        ..lineHeightAtStart = metrics.lineHeight
        ..lineHeightAtEnd = metrics.lineHeight
        ..selectionEndpoints = endpoints;
      if (show) {
        overlay.showHandles();
      }
      _showToolbarIfDesired(overlay);
    });
  }

  void _showToolbarIfDesired(SelectionOverlay overlay) {
    if (!_toolbarDesired || overlay.toolbarIsVisible) return;
    overlay.showToolbar(context: context, contextMenuBuilder: _buildToolbar);
  }

  List<TextSelectionPoint>? _selectionEndpoints(
    _SelectionChromeGeometry metrics,
  ) {
    final start = metrics.start;
    final end = metrics.end;
    if (start == null || end == null) return null;
    return <TextSelectionPoint>[
      TextSelectionPoint(start, TextDirection.ltr),
      TextSelectionPoint(end, TextDirection.ltr),
    ];
  }

  Widget _buildToolbar(BuildContext overlayContext) {
    final metrics = _chromeGeometry;
    final endpoints = metrics == null ? null : _selectionEndpoints(metrics);
    final renderObject = context.findRenderObject();
    if (metrics == null || endpoints == null || renderObject is! RenderBox) {
      return const SizedBox.shrink();
    }
    final anchors = TextSelectionToolbarAnchors.fromSelection(
      renderBox: renderObject,
      startGlyphHeight: metrics.lineHeight,
      endGlyphHeight: metrics.lineHeight,
      selectionEndpoints: endpoints,
    );
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            _overlay?.hideToolbar();
            widget.onCopy();
          },
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            _overlay?.hideToolbar();
            widget.onPaste();
          },
        ),
      ],
    );
  }

  void _onStartDragStart(DragStartDetails _) {
    final start = _chromeGeometry?.start;
    final renderObject = context.findRenderObject();
    if (start == null || renderObject is! RenderBox) return;
    _startDragGlobal = renderObject.localToGlobal(start);
    _toolbarDesired = false;
    _overlay?.hideToolbar();
  }

  void _onStartDragUpdate(DragUpdateDetails details) {
    final current = _startDragGlobal;
    final metrics = _chromeGeometry;
    final renderObject = context.findRenderObject();
    if (current == null || metrics == null || renderObject is! RenderBox) {
      return;
    }
    _startDragGlobal = current + details.delta;
    _updateDraggingEndpoint(start: true);
  }

  void _onStartDragEnd(DragEndDetails _) {
    _stopAutoScroll();
    _startDragGlobal = null;
    _toolbarDesired = true;
    _scheduleOverlayUpdate(show: true);
  }

  void _onEndDragStart(DragStartDetails _) {
    final end = _chromeGeometry?.end;
    final renderObject = context.findRenderObject();
    if (end == null || renderObject is! RenderBox) return;
    _endDragGlobal = renderObject.localToGlobal(end);
    _toolbarDesired = false;
    _overlay?.hideToolbar();
  }

  void _onEndDragUpdate(DragUpdateDetails details) {
    final current = _endDragGlobal;
    final metrics = _chromeGeometry;
    final renderObject = context.findRenderObject();
    if (current == null || metrics == null || renderObject is! RenderBox) {
      return;
    }
    _endDragGlobal = current + details.delta;
    _updateDraggingEndpoint(start: false);
  }

  void _onEndDragEnd(DragEndDetails _) {
    _stopAutoScroll();
    _endDragGlobal = null;
    _toolbarDesired = true;
    _scheduleOverlayUpdate(show: true);
  }

  void _scheduleDraggingEndpointRefresh() {
    if (_startDragGlobal == null && _endDragGlobal == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_startDragGlobal != null) {
        _updateDraggingEndpoint(start: true);
      } else if (_endDragGlobal != null) {
        _updateDraggingEndpoint(start: false);
      }
    });
  }

  void _updateDraggingEndpoint({required bool start}) {
    final global = start ? _startDragGlobal : _endDragGlobal;
    final metrics = _chromeGeometry;
    final renderObject = context.findRenderObject();
    if (global == null || metrics == null || renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(
      global - Offset(0, metrics.lineHeight / 2),
    );
    _updateAutoScroll(local);
    final cell = widget.geometry.clampedCellAt(local);
    if (cell == null) return;
    final point = widget.viewport.pointAt(cell.row, cell.column);
    if (point == null) return;
    final ordered = widget.range.ordered;
    if (start) {
      if (point != ordered.start) widget.onStartChanged(point);
    } else if (point != ordered.end) {
      widget.onEndChanged(point);
    }
  }

  void _updateAutoScroll(Offset local) {
    final rows = widget.geometry.selectionEdgeScrollRows(local);
    if (rows == _autoScrollRows) return;
    _stopAutoScroll();
    if (rows == 0) return;
    _autoScrollRows = rows;
    widget.onAutoScrollRows(rows);
    _autoScrollTimer = Timer.periodic(_autoScrollInterval, (_) {
      if (!mounted || (_startDragGlobal == null && _endDragGlobal == null)) {
        _stopAutoScroll();
        return;
      }
      widget.onAutoScrollRows(_autoScrollRows);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollRows = 0;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _chromeGeometry;
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformTarget(
              link: _toolbarLink,
              child: const SizedBox.shrink(),
            ),
          ),
          if (metrics?.start case final start?)
            Positioned(
              left: start.dx,
              top: start.dy,
              child: CompositedTransformTarget(
                link: _startLink,
                child: const SizedBox.shrink(),
              ),
            ),
          if (metrics?.end case final end?)
            Positioned(
              left: end.dx,
              top: end.dy,
              child: CompositedTransformTarget(
                link: _endLink,
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

final class _SelectionChromeGeometry {
  const _SelectionChromeGeometry({
    required this.start,
    required this.end,
    required this.startVisible,
    required this.endVisible,
    required this.lineHeight,
  });

  final Offset? start;
  final Offset? end;
  final bool startVisible;
  final bool endVisible;
  final double lineHeight;
}
