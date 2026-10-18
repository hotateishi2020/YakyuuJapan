import 'package:http/http.dart' as http;

const serverNotRunningMessage = 'サーバーが起動されていません';

void Function(Object error, StackTrace stack)? onNetworkError;

String networkErrorMessage(Object error, {required String fallback}) {
  onNetworkError?.call(error, StackTrace.current);
  return error is http.ClientException ? serverNotRunningMessage : fallback;
}
