import 'package:flutter/services.dart';

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
  TerminalTextInputClient({required this.onCommit});

  final void Function(String text) onCommit;
  final CommittedTextStager _stager = CommittedTextStager();
  TextInputConnection? _connection;

  bool get attached => _connection?.attached ?? false;

  void attach() {
    if (attached) return;
    _stager.reset();
    final connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.text,
        inputAction: TextInputAction.none,
        autocorrect: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        enableSuggestions: false,
        enableInteractiveSelection: false,
        enableIMEPersonalizedLearning: false,
      ),
    );
    _connection = connection;
    connection.setEditingState(_stager.value);
    connection.show();
  }

  void detach() {
    _connection?.close();
    _connection = null;
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
    _stager.reset();
  }

  @override
  bool onFocusReceived() => true;

  @override
  void insertTextPlaceholder(Size size) {}
}
