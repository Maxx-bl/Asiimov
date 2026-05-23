import 'package:http/http.dart' as http;

void main() async {
  try {
    final response = await http.get(Uri.parse('https://asiimov-upload.max13-bl.workers.dev/'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
