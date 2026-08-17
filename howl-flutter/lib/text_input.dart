import 'package:flutter/services.dart';

import 'platform_input.dart';

final class CommittedTextStager {
  TextEditingValue _value = TextEditingValue.empty;

  TextEditingValue get value => _value;

  String? update(TextEditingValue next) {
    _value = next;
    if (next.composing.isValid && !next.composing.isCollapsed) return null;
    if (next.text.isEmpty) return null;
    final committed = next.text;
    _value = TextEditingValue.empty;
    return committed;
  }

  void reset() {
    _value = TextEditingValue.empty;
  }
}

final class TerminalTextInputClient with TextInputClient {
  TerminalTextInputClient({
    required this.onCommit,
    this.inputType = TextInputType.text,
  });

  final void Function(String text) onCommit;
  final TextInputType inputType;
  final CommittedTextStager _stager = CommittedTextStager();
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
    final committed = _stager.update(value);
    if (committed == null) return;
    _connection?.setEditingState(_stager.value);
    onCommit(committed);
  }

  @override
  void performAction(TextInputAction action) {}

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
