String normalizeBaseUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Server URL is required.');
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(withScheme);

  if (uri == null || uri.host.isEmpty) {
    throw const FormatException('Enter a valid UpSnap server URL.');
  }

  final normalizedPath = uri.path.replaceFirst(RegExp(r'/$'), '');
  final normalized = uri.replace(path: normalizedPath).toString();

  return normalized.replaceFirst(RegExp(r'/$'), '');
}
