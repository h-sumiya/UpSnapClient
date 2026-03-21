import 'package:pocketbase/pocketbase.dart';

String errorMessage(Object error, {String fallback = 'Unexpected error'}) {
  if (error is ClientException) {
    final responseMessage = error.response['message']?.toString();
    final responseData = error.response['data'];
    if (responseData is Map<String, dynamic>) {
      for (final value in responseData.values) {
        if (value is Map<String, dynamic> && value['message'] != null) {
          return value['message'].toString();
        }
      }
    }

    if (responseMessage != null && responseMessage.isNotEmpty) {
      return responseMessage;
    }

    if (error.originalError != null) {
      return error.originalError.toString();
    }
  }

  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? fallback : text;
}
