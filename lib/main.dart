import 'package:flutter/material.dart';

void main() {
  runApp(const BookfinApp());
}

class BookfinApp extends StatelessWidget {
  const BookfinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bookfin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF775035),
          onPrimary: Color(0xFFFFF9EF),
          surface: Color(0xFFF6EFE2),
          onSurface: Color(0xFF39291F),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6EFE2),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined, size: 64),
                  SizedBox(height: 24),
                  Text('Bookfin', style: TextStyle(fontSize: 36)),
                  SizedBox(height: 12),
                  Text(
                    'Your library starts here.',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  SizedBox(
                    width: 320,
                    child: Text(
                      'Library connection is not available in this setup build.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
