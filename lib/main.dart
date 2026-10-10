import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'config/app_design.dart';
import 'logic/auth_session.dart';
import 'pages/prediction_page.dart';

void main() {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(AuthSession.instance.reportTimeout(details.exception, details.stack));
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(AuthSession.instance.reportTimeout(error, stack));
    return previousPlatform?.call(error, stack) ?? false;
  };
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    ALL_WIDTH = MediaQuery.of(context).size.width;
    return MaterialApp(
      title: 'Yakyuu! Japan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(child: PredictionPage()),
      ),
    );
  }
}
