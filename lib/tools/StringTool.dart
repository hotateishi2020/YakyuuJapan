class StringTool {
  static bool isKatakana(String str) {
    final regex = RegExp(r'^[\u30A0-\u30FF]+$');
    return regex.hasMatch(str);
  }

  static String noSpace(String str) {
    return str.replaceAll(RegExp(r'[\s\u3000]+'), '');
  }
}
