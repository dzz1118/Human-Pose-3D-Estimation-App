import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/clinical_result.dart';

class ApiService {
  // Change this if the backend runs on a different host/port.
  static const String baseUrl = 'http://localhost:8000';

  /// Upload [videoFile] to the WHAM backend.
  /// Returns the [job_id] string on success.
  static Future<String> uploadVideo(File videoFile) async {
    final uri = Uri.parse('$baseUrl/process_video');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));

    final streamed = await request.send().timeout(const Duration(minutes: 10));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Upload failed (${streamed.statusCode}): $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['job_id'] as String;
  }

  /// Poll job status for [jobId].
  /// Returns the raw status map (keys: status, error_type, error, …).
  static Future<Map<String, dynamic>> getStatus(String jobId) async {
    final uri = Uri.parse('$baseUrl/status/$jobId');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Status check failed (${response.statusCode}): ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Fetch the parsed WHAM result for [jobId] (only valid when status == done).
  static Future<ClinicalResult> getResults(String jobId) async {
    final uri = Uri.parse('$baseUrl/results/$jobId');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Results fetch failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ClinicalResult.fromWhamJson(json);
  }
}
