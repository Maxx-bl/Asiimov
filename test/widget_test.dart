import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:asiimov/themes/theme_provider.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('ThemeProvider builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Test')),
          ),
        ),
      ),
    );
    expect(find.text('Test'), findsOneWidget);
  });
}
