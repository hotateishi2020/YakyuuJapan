import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

const _smtpUser = 'hotateishi2012@yahoo.co.jp';
const _smtpPassword = '199424';
const _errorInbox = 'hotateishi2018@gmail.com';

Future<void> sendOutboundMail({
  required String to,
  required String subject,
  required String text,
}) async {
  final smtpServer = SmtpServer(
    'smtp.mail.yahoo.co.jp',
    port: 465,
    ssl: true,
    username: _smtpUser,
    password: _smtpPassword,
  );
  final message = Message()
    ..from = const Address(_smtpUser, 'YakyuuJapan')
    ..recipients.add(to)
    ..subject = subject
    ..text = text;
  await send(message, smtpServer);
}

Future<void> sendProgramErrorMail(Object error) {
  return sendOutboundMail(
    to: _errorInbox,
    subject: 'プログラム上でエラーが発生しました',
    text: error.toString(),
  );
}

/// 試合読み込みが成功したときの所要時間。宛先はエラー通知と同じ。
Future<void> sendFetchDurationMail({
  required String label,
  required Duration elapsed,
  required String result,
}) {
  final seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
  return sendOutboundMail(
    to: _errorInbox,
    subject: '試合読み込み成功 ($label)',
    text: '$label の試合読み込みが成功しました。\n所要時間: $seconds 秒\n結果: $result',
  );
}
