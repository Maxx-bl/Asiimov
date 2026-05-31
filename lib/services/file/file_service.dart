import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const int kUploadQuotaWindowHours = 48;
const int kUploadQuotaLimitBytes = 250 * 1024 * 1024; // 250 MB

class QuotaExceededException implements Exception {
  final int usedBytes;
  final int limitBytes;
  QuotaExceededException(this.usedBytes, this.limitBytes);
}

class FileService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  static const int maxFileSizeInBytes = 20 * 1024 * 1024; // 20 MB per file

  static const String _workerUrl =
      "https://asiimov-upload.max13-bl.workers.dev/";
  static const String _r2PublicDomain =
      "https://pub-47957f69f37d442487db8f16fb7d957f.r2.dev";

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
            throw Exception(
                'File ${platformFile.name} exceeds the 20MB limit.');
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

  // ─── Image compression ────────────────────────────────────────────────────

  static const List<String> _imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp'
  ];
  static const int maxImageSizeInBytes = 1 * 1024 * 1024; // 1 MB target

  Future<File> _compressImageIfNeeded(File file, String extension) async {
    if (!_imageExtensions.contains(extension)) return file;
    final size = await file.length();
    if (size <= maxImageSizeInBytes) return file;

    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/chat_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    for (final quality in [80, 60, 40]) {
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: 1280,
        minHeight: 1280,
        format: CompressFormat.jpeg,
      );
      if (result == null) break;
      final compressed = File(result.path);
      if (await compressed.length() <= maxImageSizeInBytes) return compressed;
    }

    final fallback = File(targetPath);
    return await fallback.exists() ? fallback : file;
  }

  // ─── Upload quota ─────────────────────────────────────────────────────────

  /// Checks quota then atomically records the upload in Firestore.
  /// Throws [QuotaExceededException] if the limit would be exceeded.
  Future<void> _checkAndRecordQuota(String uid, int bytes) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? {};
      final quotaData = data['uploadQuota'] as Map<String, dynamic>?;

      final now = DateTime.now();
      final windowStart = quotaData?['windowStart'] != null
          ? (quotaData!['windowStart'] as Timestamp).toDate()
          : null;

      final inWindow = windowStart != null &&
          now.difference(windowStart).inHours < kUploadQuotaWindowHours;

      final usedBytes = inWindow ? ((quotaData?['bytesUsed'] as int?) ?? 0) : 0;

      if (usedBytes + bytes > kUploadQuotaLimitBytes) {
        throw QuotaExceededException(usedBytes, kUploadQuotaLimitBytes);
      }

      tx.update(userRef, {
        'uploadQuota': {
          'bytesUsed': usedBytes + bytes,
          'windowStart':
              inWindow ? quotaData!['windowStart'] : Timestamp.fromDate(now),
        }
      });
    });
  }

  // ─── Upload ───────────────────────────────────────────────────────────────

  /// Upload a file to Cloudflare R2 securely.
  /// Pass [skipQuota] = true for instant-camera photos (excluded from quota).
  Future<Map<String, dynamic>?> uploadChatAttachment(
    File file,
    String chatRoomId, {
    bool skipQuota = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final dotIndex = fileName.lastIndexOf('.');
      final extension =
          dotIndex != -1 ? fileName.substring(dotIndex).toLowerCase() : '';

      final fileToUpload = await _compressImageIfNeeded(file, extension);
      final fileBytes = await fileToUpload.readAsBytes();

      if (fileBytes.length > maxFileSizeInBytes) {
        throw Exception('File exceeds the 20MB limit.');
      }

      if (!skipQuota) {
        await _checkAndRecordQuota(user.uid, fileBytes.length);
      }

      final idToken = await user.getIdToken();
      final uniqueId = const Uuid().v4();

      final String folder = (chatRoomId == 'voice')
          ? 'voice_files'
          : (chatRoomId == 'post' || chatRoomId == 'comment')
              ? 'post_files'
              : 'chat_files';

      final objectKey = '$folder/${user.uid}/${uniqueId}_$fileName';

      final cleanWorkerUrl = _workerUrl.endsWith('/')
          ? _workerUrl.substring(0, _workerUrl.length - 1)
          : _workerUrl;

      final response = await http.put(
        Uri.parse('$cleanWorkerUrl/$objectKey'),
        headers: {'Authorization': 'Bearer $idToken'},
        body: fileBytes,
      );

      if (response.statusCode != 200) {
        debugPrint(
            "Failed to upload attachment: ${response.statusCode} - ${response.body}");
        return null;
      }

      final downloadUrl = "$_r2PublicDomain/$objectKey";

      String type = 'document';
      if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(extension)) {
        type = 'image';
      } else if (['.mp4', '.mov', '.avi', '.mkv'].contains(extension)) {
        type = 'video';
      } else if (['.m4a', '.aac', '.mp3', '.wav', '.ogg', '.flac']
          .contains(extension)) {
        type = 'audio';
      }

      return {
        'url': downloadUrl,
        'type': type,
        'name': fileName,
        'size': fileBytes.length,
        'objectKey': objectKey,
      };
    } catch (e) {
      // Re-throw quota exceptions so callers can show the proper UI
      if (e is QuotaExceededException) rethrow;
      debugPrint("Error uploading chat attachment: $e");
      return null;
    }
  }

  /// Delete all chat files for the current user (chat_files/{uid}/) from R2.
  /// Also resets their upload quota in Firestore.
  Future<bool> clearMyChatFiles() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final idToken = await user.getIdToken();
      final cleanWorkerUrl = _workerUrl.endsWith('/')
          ? _workerUrl.substring(0, _workerUrl.length - 1)
          : _workerUrl;

      // Trailing slash triggers bulk-delete on the Worker
      final response = await http.delete(
        Uri.parse('$cleanWorkerUrl/chat_files/${user.uid}/'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

      if (response.statusCode != 200) return false;

      // Reset quota window in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'uploadQuota': FieldValue.delete()});

      return true;
    } catch (e) {
      debugPrint("Error clearing chat files: $e");
      return false;
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
        headers: {'Authorization': 'Bearer $idToken'},
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error deleting attachment: $e");
      return false;
    }
  }
}
