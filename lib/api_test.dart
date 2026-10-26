import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiTest extends StatefulWidget {
  const ApiTest({super.key});

  @override
  State<ApiTest> createState() => _ApiTestState();
}

class _ApiTestState extends State<ApiTest> {
  String result = 'Testing API...';

  Future<void> testApi() async {
    const String url =
        // 'http://192.168.1.48/citisense/api/test_api.php';
        'http://10.127.214.252/citisense/api/test_api.php';
    try {
      final response = await http.get(Uri.parse(url));

      print('==============================');
      print('STATUS CODE: ${response.statusCode}');
      print('CONTENT TYPE: ${response.headers['content-type']}');
      print('BODY:');
      print(response.body);
      print('==============================');

      setState(() {
        result =
            'STATUS CODE:\n${response.statusCode}\n\n'
            'CONTENT TYPE:\n${response.headers['content-type']}\n\n'
            'RAW RESPONSE:\n${response.body}';
      });
    } catch (e) {
      print('==============================');
      print('REQUEST ERROR:');
      print(e);
      print('==============================');

      setState(() {
        result = 'REQUEST ERROR:\n\n$e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    testApi();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(result, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
