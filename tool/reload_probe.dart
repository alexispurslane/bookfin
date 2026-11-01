import 'package:flutter/material.dart';

void main() {
  runApp(const ReloadProbe());
}

class ReloadProbe extends StatelessWidget {
  const ReloadProbe({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bookfin reload probe',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF775035),
        scaffoldBackgroundColor: const Color(0xFFF6EFE2),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(32),
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Bookfin setup probe'),
                    SizedBox(height: 16),
                    Text('Reload marker: before'),
                    SizedBox(height: 24),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Shared setup note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Temporary test fixture. The note is not saved.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
