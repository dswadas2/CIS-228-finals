import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/main.dart'; // Make sure this matches your actual package name

void main() {
  testWidgets('GestureMusicApp renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: GestureMusicApp()));

    // Check if "Gesture Music Player" text appears in the UI
    expect(find.text("Gesture Music Player"), findsOneWidget);
  });
}