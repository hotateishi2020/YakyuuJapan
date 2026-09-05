import 'package:flutter/material.dart';
import 'config/app_design.dart';
import 'pages/prediction_page.dart';

void main() {
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
