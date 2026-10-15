import 'package:http/http.dart' as http;

const serverNotRunningMessage = 'サーバーが起動されていません';

String networkErrorMessage(Object error, {required String fallback}) =>
    error is http.ClientException ? serverNotRunningMessage : fallback;
