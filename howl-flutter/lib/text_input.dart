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
  const TerminalEditKeyAction(this.key);

  final TerminalEditKey key;
}

/// Small platform-editing model for a terminal, not a retained text document.
///
/// Android IMEs commonly express Backspace/Delete as document edits rather than
/// key events. Two private-use guard scalars keep those edits observable while
/// the cursor sits between them. Guards never leave this model. Active IME
/// composition remains local; once composition commits, only the text between
/// the guards is emitted and the canonical guard value is restored.
final class TerminalInputStager {
  static const leftGuard = '\uE000';
  static const rightGuard = '\uE001';
  static const guardText = '$leftGuard$rightGuard';
  static const canonicalValue = TextEditingValue(
    text: guardText,
    selection: TextSelection.collapsed(offset: 1),
  );

  TextEditingValue _value = canonicalValue;

  TextEditingValue get value => _value;

  List<TerminalInputAction> update(TextEditingValue next) {
    _value = next;
    if (next.composing.isValid && !next.composing.isCollapsed) {
      return const <TerminalInputAction>[];
    }

    final text = next.text;
    final actions = <TerminalInputAction>[];
    if (text == rightGuard) {
      actions.add(const TerminalEditKeyAction(TerminalEditKey.backspace));
    } else if (text == leftGuard) {
      actions.add(const TerminalEditKeyAction(TerminalEditKey.delete));
    } else if (text.startsWith(leftGuard) && text.endsWith(rightGuard)) {
      final committed = text.substring(
        leftGuard.length,
        text.length - rightGuard.length,
      );
      if (!committed.contains(leftGuard) && !committed.contains(rightGuard)) {
        actions.addAll(_committedActions(committed));
      }
    } else if (!text.contains(leftGuard) && !text.contains(rightGuard)) {
      // Some IMEs replace the entire editable on commit instead of preserving
      // surrounding content. Empty replacement is ambiguous and intentionally
      // produces no terminal action.
      actions.addAll(_committedActions(text));
    }

    _value = canonicalValue;
    return actions;
  }

  void reset() {
    _value = canonicalValue;
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

final class TerminalTextInputClient with TextInputClient {
  TerminalTextInputClient({
    required this.onCommit,
    required this.onEditKey,
    this.inputType = TextInputType.text,
  });

  final void Function(String text) onCommit;
  final void Function(TerminalEditKey key) onEditKey;
  final TextInputType inputType;
  final TerminalInputStager _stager = TerminalInputStager();
  TextInputConnection? _connection;
  int? _viewId;

  bool get attached => _connection?.attached ?? false;

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
        case TerminalEditKeyAction(:final key):
          onEditKey(key);
      }
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) onEditKey(TerminalEditKey.enter);
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
