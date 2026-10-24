String normalizeCardUid(String value) {
  final uid = value.toUpperCase().replaceAll(RegExp(r'[:\-\s]'), '');
  if (!RegExp(r'^([0-9A-F]{2}){1,32}$').hasMatch(uid)) {
    throw const FormatException('UID thẻ không hợp lệ.');
  }
  return uid;
}
