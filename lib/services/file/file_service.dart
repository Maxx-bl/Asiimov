import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class FileService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();
  
  static const int maxFileSizeInBytes = 20 * 1024 * 1024; // 20 MB

  // Should match image_service
  static const String _workerUrl = "https://asiimov-upload.max13-bl.workers.dev/";
  static const String _r2PublicDomain = "https://pub-47957f69f37d442487db8f16fb7d957f.r2.dev";

  /// Pick multiple images/videos from Gallery
  Future<List<File>> pickGalleryMedia() async {
    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultipleMedia();
      List<File> validFiles = [];

      for (var xFile in pickedFiles) {
        final length = await xFile.length();
        if (length > maxFileSizeInBytes) {
          throw Exception('File ${xFile.name} exceeds the 20MB limit.');
        }
        validFiles.add(File(xFile.path));
      }
      
      if (validFiles.length > 10) {
        throw Exception('You can only select up to 10 files at once.');
      }
      return validFiles;
    } catch (e) {
      debugPrint("Error picking gallery media: $e");
      rethrow;
    }
  }

  /// Pick multiple documents (PDF, etc.)
  Future<List<File>> pickDocuments() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null) {
        List<File> validFiles = [];
        for (var platformFile in result.files) {
          if (platformFile.path == null) continue;
          if (platformFile.size > maxFileSizeInBytes) {
            throw Exception('File ${platformFile.name} exceeds the 20MB limit.');
          }
          validFiles.add(File(platformFile.path!));
        }
        
        if (validFiles.length > 10) {
          throw Exception('You can only select up to 10 files at once.');
        }
        return validFiles;
      }
      return [];
    } catch (e) {
      debugPrint("Error picking documents: $e");
      rethrow;
    }
  }

  /// Upload a file to Cloudflare R2 securely
  Future<Map<String, dynamic>?> uploadChatAttachment(File file, String chatRoomId) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final fileBytes = await file.readAsBytes();
      if (fileBytes.length > maxFileSizeInBytes) {
        throw Exception('File exceeds the 20MB limit.');
      }

      final idToken = await user.getIdToken();
      
      final fileName = file.path.split(Platform.pathSeparator).last;
      final dotIndex = fileName.lastIndexOf('.');
      final extension = dotIndex != -1 ? fileName.substring(dotIndex).toLowerCase() : '';
      final uniqueId = const Uuid().v4();
      
      // We store chat files under chat_files/UID/UNIQUE_ID_FILENAME
      // This allows the Worker to verify that the user uploading/deleting owns the directory
      final objectKey = 'chat_files/${user.uid}/${uniqueId}_$fileName';

      final cleanWorkerUrl = _workerUrl.endsWith('/') 
          ? _workerUrl.substring(0, _workerUrl.length - 1) 
          : _workerUrl;
          
      final response = await http.put(
        Uri.parse('$cleanWorkerUrl/$objectKey'),
        headers: {
          'Authorization': 'Bearer $idToken',
          // Optionally set content type based on extension
        },
        body: fileBytes,
      );

      if (response.statusCode != 200) {
        debugPrint("Failed to upload attachment: ${response.statusCode} - ${response.body}");
        return null;
      }

      final downloadUrl = "$_r2PublicDomain/$objectKey";
      
      // Determine type
      String type = 'document';
      if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(extension)) {
        type = 'image';
      } else if (['.mp4', '.mov', '.avi', '.mkv'].contains(extension)) {
        type = 'video';
      }

      return {
        'url': downloadUrl,
        'type': type,
        'name': fileName,
        'size': fileBytes.length,
        'objectKey': objectKey,
      };
    } catch (e) {
      debugPrint("Error uploading chat attachment: $e");
      return null;
    }
  }

  /// Delete a file from Cloudflare R2
  Future<bool> deleteAttachment(String objectKey) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final idToken = await user.getIdToken();
      final cleanWorkerUrl = _workerUrl.endsWith('/') 
          ? _workerUrl.substring(0, _workerUrl.length - 1) 
          : _workerUrl;

      final response = await http.delete(
        Uri.parse('$cleanWorkerUrl/$objectKey'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error deleting attachment: $e");
      return false;
    }
  }
}
