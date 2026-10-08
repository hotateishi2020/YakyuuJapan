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
    ..from = Address(_smtpUser, 'YakyuuJapan')
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
