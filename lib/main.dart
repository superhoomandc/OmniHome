import 'package:flutter/material.dart';
import 'views/home/home_page.dart';

void main() {
  runApp(const LightControlApp());
}

class LightControlApp extends StatelessWidget {
  const LightControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniHome',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LightControlPage(title: 'OmniHome'),
    );
  }
}