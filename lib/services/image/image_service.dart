import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ImageService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  // Cloudflare Worker URL for Secure Proxy Upload (TODO: Remplir avec l'URL de ton Worker)
  static const String _workerUrl = "https://asiimov-upload.max13-bl.workers.dev/";
  
  // URL publique générée par ton R2 bucket pour la lecture
  static const String _r2PublicDomain = "https://pub-47957f69f37d442487db8f16fb7d957f.r2.dev";

  // In-memory cache for profile picture URLs (avoids Firestore reads)
  static final Map<String, String?> _profileUrlCache = {};

  /// Pick an image from the given source (camera or gallery)
  Future<XFile?> pickImage(ImageSource source) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint("Error picking image: $e");
      return null;
    }
  }

  /// Compress an image file to reduce size for upload.
  /// Target: ~100-200KB for profile pictures.
  Future<File?> compressImage(File file, {int quality = 70, int minWidth = 400, int minHeight = 400}) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
        format: CompressFormat.jpeg,
      );

      if (result != null) {
        return File(result.path);
      }
      return null;
    } catch (e) {
      debugPrint("Error compressing image: $e");
      return null;
    }
  }

  /// Upload a profile picture securely via Cloudflare Worker proxy.
  Future<String?> uploadProfilePicture(File imageFile) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    if (_workerUrl.contains("TODO")) {
      debugPrint("ERROR: Cloudflare Worker URL is missing!");
      return null;
    }

    try {
      // 1. Compress image locally to preserve bandwidth
      final compressed = await compressImage(
        imageFile,
        quality: 70,
        minWidth: 400,
        minHeight: 400,
      );
      final fileToUpload = compressed ?? imageFile;
      final fileBytes = await fileToUpload.readAsBytes();

      // 2. Fetch Firebase ID Token for secure Auth verification in Worker
      final idToken = await user.getIdToken();

      // 3. Upload to Cloudflare Worker securely
      final objectKey = 'profile_pictures/${user.uid}.jpg';
      final cleanWorkerUrl = _workerUrl.endsWith('/') 
          ? _workerUrl.substring(0, _workerUrl.length - 1) 
          : _workerUrl;
          
      final response = await http.put(
        Uri.parse('$cleanWorkerUrl/$objectKey'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'image/jpeg',
        },
        body: fileBytes,
      );

      if (response.statusCode != 200) {
        debugPrint("Failed to upload to Worker: ${response.statusCode} - ${response.body}");
        return null;
      }

      // 4. Construct the public URL for downloading (via R2 CDN directly)
      // We append a timestamp '?v=' so CachedNetworkImage bypasses disk cache when the picture is updated
      final downloadUrl = "$_r2PublicDomain/$objectKey?v=${DateTime.now().millisecondsSinceEpoch}";

      // 5. Update Firebase Auth profile
      await user.updatePhotoURL(downloadUrl);

      // 6. Update Firestore user document
      await _firestore.collection('users').doc(user.uid).update({
        'profilePictureUrl': downloadUrl,
      });

      // 7. Update local cache
      _profileUrlCache[user.uid] = downloadUrl;

      // 8. Clean up temp file
      if (compressed != null && await compressed.exists()) {
        await compressed.delete();
      }

      return downloadUrl;
    } catch (e) {
      debugPrint("Error uploading profile picture to R2: $e");
      return null;
    }
  }

  /// Delete the current user's profile picture.
  /// Clears the photoURL in Firebase Auth and Firestore.
  Future<bool> deleteProfilePicture() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Update Firebase Auth profile
      await user.updatePhotoURL(null);

      // 2. Update Firestore user document (set to empty string so it falls back to initial letter)
      await _firestore.collection('users').doc(user.uid).update({
        'profilePictureUrl': '',
      });

      // 3. Clear local cache
      _profileUrlCache[user.uid] = '';

      return true;
    } catch (e) {
      debugPrint("Error deleting profile picture: $e");
      return false;
    }
  }

  /// Upload a group profile picture securely via Cloudflare Worker proxy.
  Future<String?> uploadGroupProfilePicture(String groupId, File imageFile) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    if (_workerUrl.contains("TODO")) {
      debugPrint("ERROR: Cloudflare Worker URL is missing!");
      return null;
    }

    try {
      // 1. Compress image locally to preserve bandwidth
      final compressed = await compressImage(
        imageFile,
        quality: 70,
        minWidth: 400,
        minHeight: 400,
      );
      final fileToUpload = compressed ?? imageFile;
      final fileBytes = await fileToUpload.readAsBytes();

      // 2. Fetch Firebase ID Token for secure Auth verification in Worker
      final idToken = await user.getIdToken();

      // 3. Upload to Cloudflare Worker securely
      final objectKey = 'chat_files/${user.uid}/group_$groupId.jpg';
      final cleanWorkerUrl = _workerUrl.endsWith('/') 
          ? _workerUrl.substring(0, _workerUrl.length - 1) 
          : _workerUrl;
          
      final response = await http.put(
        Uri.parse('$cleanWorkerUrl/$objectKey'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'image/jpeg',
        },
        body: fileBytes,
      );

      if (response.statusCode != 200) {
        debugPrint("Failed to upload group pfp to Worker: ${response.statusCode} - ${response.body}");
        return null;
      }

      // 4. Construct the public URL for downloading (via R2 CDN directly)
      final downloadUrl = "$_r2PublicDomain/$objectKey?v=${DateTime.now().millisecondsSinceEpoch}";

      // 5. Update Firestore group document
      await _firestore.collection('chats').doc(groupId).update({
        'groupIconUrl': downloadUrl,
      });

      // 6. Clean up temp file
      if (compressed != null && await compressed.exists()) {
        await compressed.delete();
      }

      return downloadUrl;
    } catch (e) {
      debugPrint("Error uploading group profile picture to R2: $e");
      return null;
    }
  }

  /// Delete a group profile picture.
  Future<bool> deleteGroupProfilePicture(String groupId) async {
    try {
      await _firestore.collection('chats').doc(groupId).update({
        'groupIconUrl': '',
      });
      return true;
    } catch (e) {
      debugPrint("Error deleting group profile picture: $e");
      return false;
    }
  }

  /// Get a user's profile picture URL (with in-memory cache).
  /// Returns null if no profile picture is set.
  Future<String?> getProfilePictureUrl(String userId) async {
    // Check memory cache first
    if (_profileUrlCache.containsKey(userId)) {
      return _profileUrlCache[userId];
    }

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final url = doc.data()?['profilePictureUrl'] as String?;
      _profileUrlCache[userId] = url;
      return url;
    } catch (e) {
      debugPrint("Error getting profile picture URL: $e");
      return null;
    }
  }

  /// Invalidate the cache for a specific user (e.g. after upload)
  void invalidateCache(String userId) {
    _profileUrlCache.remove(userId);
  }

  /// Clear the entire profile picture cache
  static void clearCache() {
    _profileUrlCache.clear();
  }

  /// Show a bottom sheet to pick image source (camera, gallery, or delete)
  static Future<String?> showImageSourceSheet(BuildContext context, {bool showDeleteOption = false}) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Change Profile Picture',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade200,
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              if (showDeleteOption)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.redAccent,
                    child: Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  title: const Text('Delete Current Photo', style: TextStyle(color: Colors.redAccent)),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
