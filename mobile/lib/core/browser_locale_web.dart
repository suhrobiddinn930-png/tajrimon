import 'dart:js_interop';

@JS('document.documentElement.lang')
external set _documentLanguage(JSString value);

void updateDocumentLanguage(String language) {
  _documentLanguage = language.toJS;
}
