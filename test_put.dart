import 'package:http/http.dart' as http;
import 'dart:io';

void main() async {
  try {
    final file = File('dummy.jpg');
    await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xDB]); // fake jpeg header
    final bytes = await file.readAsBytes();
    
    final response = await http.put(
      Uri.parse('https://asiimov-upload.max13-bl.workers.dev/test.jpg'),
      headers: {
        'Authorization': 'Bearer fake_token',
        'Content-Type': 'image/jpeg',
      },
      body: bytes,
    );
    
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
