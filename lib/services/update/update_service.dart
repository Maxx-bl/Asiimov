import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum UpdateStatus {
  upToDate,
  recommended,
  required,
}

class UpdateService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> initialize() async {
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: Duration.zero, // Set to 0 to fetch instantly during testing
    ));

    try {
      await _remoteConfig.setDefaults(const {
        'force_update_version': '0.0.0',
        'recommanded_update_version': '0.0.0',
        'app_download_url': '',
      });
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      print('Failed to fetch remote config: $e');
    }
  }

  Future<UpdateStatus> getUpdateStatus() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final forceVersion = _remoteConfig.getString('force_update_version');
    final recommendedVersion = _remoteConfig.getString('recommanded_update_version');

    if (_isVersionGreaterThan(forceVersion, currentVersion)) {
      return UpdateStatus.required;
    }

    if (_isVersionGreaterThan(recommendedVersion, currentVersion)) {
      return UpdateStatus.recommended;
    }

    return UpdateStatus.upToDate;
  }

  String get downloadUrl {
    return _remoteConfig.getString('app_download_url');
  }

  bool _isVersionGreaterThan(String newVersion, String currentVersion) {
    if (newVersion.isEmpty || currentVersion.isEmpty || newVersion == '0.0.0') {
      return false;
    }

    try {
      List<int> currentParts = currentVersion.split('.').map(int.parse).toList();
      List<int> newParts = newVersion.split('.').map(int.parse).toList();

      for (int i = 0; i < newParts.length; i++) {
        int newPart = newParts[i];
        int currentPart = i < currentParts.length ? currentParts[i] : 0;

        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
