import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_input.dart';

enum TerminalEditKey { enter, backspace, delete }

sealed class TerminalInputAction {
  const TerminalInputAction();
}

final class TerminalCommittedText extends TerminalInputAction {
  const TerminalCommittedText(this.text);

  final String text;
}

final class TerminalEditKeyAction extends TerminalInputAction {
  const TerminalEditKeyAction(this.key, {this.count = 1}) : assert(count > 0);

  final TerminalEditKey key;
  final int count;
}

/// Small platform-editing model for a terminal, not a retained text document.
///
/// Android IMEs commonly express Backspace/Delete as document edits rather than
/// key events. Two private-use guard scalars keep those edits observable while
/// the cursor sits between them. Guards never leave this model. Active IME
/// composition remains local; once composition commits, only the text between
/// the guards is emitted and the canonical guard value is restored.
final class TerminalInputStager {
  TerminalInputStager({this.backspaceRunway = 1})
    : assert(backspaceRunway > 0) {
    _canonicalValue = _makeCanonicalValue(backspaceRunway);
    _value = _canonicalValue;
  }

  static const leftGuard = '\uE000';
  static const rightGuard = '\uE001';
  static const guardText = '$leftGuard$rightGuard';
  static const canonicalValue = TextEditingValue(
    text: guardText,
    selection: TextSelection.collapsed(offset: 1),
  );

  final int backspaceRunway;
  late final TextEditingValue _canonicalValue;
  late TextEditingValue _value;

  TextEditingValue get value => _value;

  static TextEditingValue _makeCanonicalValue(int backspaceRunway) {
    final left = List<String>.filled(backspaceRunway, leftGuard).join();
    return TextEditingValue(
      text: '$left$rightGuard',
      selection: TextSelection.collapsed(offset: left.length),
    );
  }

  static int _leadingLeftGuards(String text) {
    var count = 0;
    var offset = 0;
    while (text.startsWith(leftGuard, offset)) {
      count += 1;
      offset += leftGuard.length;
    }
    return count;
  }

  static int? _pureBackspaceRunway(String text) {
    if (!text.endsWith(rightGuard)) return null;
    final body = text.substring(0, text.length - rightGuard.length);
    final count = _leadingLeftGuards(body);
    if (count * leftGuard.length != body.length) return null;
    return count;
  }

  static int? _pureLeftGuards(String text) {
    final count = _leadingLeftGuards(text);
    if (count * leftGuard.length != text.length) return null;
    return count;
  }

  List<TerminalInputAction> update(TextEditingValue next) {
    final previous = _value;
    _value = next;
    if (next.composing.isValid && !next.composing.isCollapsed) {
      return const <TerminalInputAction>[];
    }

    final text = next.text;
    final actions = <TerminalInputAction>[];
    final previousRunway = _pureBackspaceRunway(previous.text);
    final nextRunway = _pureBackspaceRunway(text);
    if (nextRunway != null) {
      if (previousRunway != null && nextRunway < previousRunway) {
        final removed = previousRunway - nextRunway;
        actions.add(
          TerminalEditKeyAction(TerminalEditKey.backspace, count: removed),
        );
        final recenterAt = backspaceRunway ~/ 4;
        if (nextRunway <= recenterAt) _value = _canonicalValue;
      }
      return actions;
    }

    final nextLeftOnly = _pureLeftGuards(text);
    if (previousRunway != null && nextLeftOnly == previousRunway) {
      actions.add(const TerminalEditKeyAction(TerminalEditKey.delete));
      _value = _canonicalValue;
      return actions;
    }

    if (text.endsWith(rightGuard)) {
      final leftCount = _leadingLeftGuards(text);
      final committed = text.substring(
        leftCount * leftGuard.length,
        text.length - rightGuard.length,
      );
      actions.addAll(_safeCommittedActions(committed));
    } else if (!text.contains(leftGuard) && !text.contains(rightGuard)) {
      // Some IMEs replace the entire editable on commit instead of preserving
      // surrounding content. Empty replacement is ambiguous and intentionally
      // produces no terminal action.
      actions.addAll(_safeCommittedActions(text));
    }

    _value = _canonicalValue;
    return actions;
  }

  /// Consumes one exact native edit without treating its cumulative old text
  /// as newly committed terminal input.
  List<TerminalInputAction> updateDelta(TextEditingDelta delta) {
    final previous = _value;
    final wasComposing =
        previous.composing.isValid && !previous.composing.isCollapsed;
    final next = delta.apply(previous);
    _value = next;
    if (next.composing.isValid && !next.composing.isCollapsed) {
      return const <TerminalInputAction>[];
    }

    if (wasComposing) {
      // Linux may normalize the final commit to any delta subclass. The old
      // composing start and final collapsed caret delimit only this client's
      // preedit, excluding older committed text still retained by the engine.
      final start = previous.composing.start;
      final end = next.selection.extentOffset;
      final committed =
          next.selection.isValid &&
              next.selection.isCollapsed &&
              start >= 0 &&
              end >= start &&
              end <= next.text.length
          ? next.text.substring(start, end)
          : '';
      _value = _canonicalValue;
      return _safeCommittedActions(committed);
    }

    List<TerminalInputAction> actions;
    switch (delta) {
      case TextEditingDeltaInsertion(:final textInserted):
        actions = _safeCommittedActions(textInserted);
      case TextEditingDeltaReplacement(:final replacementText):
        actions = _safeCommittedActions(replacementText);
      case TextEditingDeltaDeletion(:final textDeleted):
        if (textDeleted.isEmpty) {
          actions = const <TerminalInputAction>[];
        } else if (textDeleted.runes.every((rune) => rune == 0xE000)) {
          actions = <TerminalInputAction>[
            TerminalEditKeyAction(
              TerminalEditKey.backspace,
              count: textDeleted.runes.length,
            ),
          ];
        } else if (textDeleted.runes.every((rune) => rune == 0xE001)) {
          actions = <TerminalInputAction>[
            TerminalEditKeyAction(
              TerminalEditKey.delete,
              count: textDeleted.runes.length,
            ),
          ];
        } else {
          actions = const <TerminalInputAction>[];
        }
      case TextEditingDeltaNonTextUpdate():
        actions = const <TerminalInputAction>[];
      default:
        actions = const <TerminalInputAction>[];
    }

    _value = _canonicalValue;
    return actions;
  }

  void reset() {
    _value = _canonicalValue;
  }

  static List<TerminalInputAction> _safeCommittedActions(String text) {
    if (text.contains(leftGuard) || text.contains(rightGuard)) {
      return const <TerminalInputAction>[];
    }
    return _committedActions(text);
  }

  static List<TerminalInputAction> _committedActions(String text) {
    if (text.isEmpty) return const <TerminalInputAction>[];
    final actions = <TerminalInputAction>[];
    var segmentStart = 0;
    var index = 0;
    while (index < text.length) {
      final codeUnit = text.codeUnitAt(index);
      if (codeUnit != 0x0a && codeUnit != 0x0d) {
        index += 1;
        continue;
      }
      if (segmentStart < index) {
        actions.add(TerminalCommittedText(text.substring(segmentStart, index)));
      }
      actions.add(const TerminalEditKeyAction(TerminalEditKey.enter));
      if (codeUnit == 0x0d &&
          index + 1 < text.length &&
          text.codeUnitAt(index + 1) == 0x0a) {
        index += 2;
      } else {
        index += 1;
      }
      segmentStart = index;
    }
    if (segmentStart < text.length) {
      actions.add(TerminalCommittedText(text.substring(segmentStart)));
    }
    return actions;
  }
}

final class TerminalTextInputClient with TextInputClient, DeltaTextInputClient {
  TerminalTextInputClient({
    required this.onCommit,
    required this.onEditKey,
    this.inputType = TextInputType.text,
    this.platformOverride,
    int backspaceRunway = 1,
  }) : _stager = TerminalInputStager(backspaceRunway: backspaceRunway);

  final void Function(String text) onCommit;
  final void Function(TerminalEditKey key, int count) onEditKey;
  final TextInputType inputType;
  final TargetPlatform? platformOverride;
  final TerminalInputStager _stager;
  TextInputConnection? _connection;
  int? _viewId;

  bool get attached => _connection?.attached ?? false;

  bool get _usesDeltaModel =>
      !kIsWeb &&
      (platformOverride ?? defaultTargetPlatform) == TargetPlatform.linux;

  TextInputConfiguration _configuration(int viewId) => TextInputConfiguration(
    viewId: viewId,
    inputType: inputType,
    inputAction: TextInputAction.none,
    autocorrect: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    enableSuggestions: false,
    enableInteractiveSelection: false,
    enableIMEPersonalizedLearning: false,
    enableDeltaModel: _usesDeltaModel,
  );

  void attach({required int viewId}) {
    final existing = _connection;
    if (existing != null && existing.attached) {
      if (_viewId != viewId) {
        existing.updateConfig(_configuration(viewId));
        _viewId = viewId;
      }
      return;
    }
    _stager.reset();
    final connection = TextInput.attach(this, _configuration(viewId));
    _connection = connection;
    _viewId = viewId;
    connection.setEditingState(_stager.value);
  }

  Future<void> show(TerminalPlatformInput platformInput) async {
    final connection = _connection;
    if (connection == null || !connection.attached) return;
    await platformInput.show(connection.show);
  }

  void detach() {
    _connection?.close();
    _connection = null;
    _viewId = null;
    _stager.reset();
  }

  @override
  TextEditingValue get currentTextEditingValue => _stager.value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    final actions = _stager.update(value);
    if (_stager.value != value) {
      _connection?.setEditingState(_stager.value);
    }
    for (final action in actions) {
      switch (action) {
        case TerminalCommittedText(:final text):
          onCommit(text);
        case TerminalEditKeyAction(:final key, :final count):
          onEditKey(key, count);
      }
    }
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    final actions = <TerminalInputAction>[];
    for (final delta in textEditingDeltas) {
      actions.addAll(_stager.updateDelta(delta));
    }
    final composing = _stager.value.composing;
    if (!composing.isValid || composing.isCollapsed) {
      _connection?.setEditingState(_stager.value);
    }
    for (final action in actions) {
      switch (action) {
        case TerminalCommittedText(:final text):
          onCommit(text);
        case TerminalEditKeyAction(:final key, :final count):
          onEditKey(key, count);
      }
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) onEditKey(TerminalEditKey.enter, 1);
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    _viewId = null;
    _stager.reset();
  }

  @override
  bool onFocusReceived() => true;

  @override
  void insertTextPlaceholder(Size size) {}
}
