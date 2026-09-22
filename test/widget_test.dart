import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:custom_field_compare/main.dart';

void main() {
  testWidgets('renders split compare view with sandbox and production panels', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Sandbox'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Load Sandbox JSON'), findsOneWidget);
    expect(find.text('Load Production JSON'), findsOneWidget);
    expect(find.text('No file loaded'), findsNWidgets(2));
  });
}
