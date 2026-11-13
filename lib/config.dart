/// App-wide links and the build number injected by GitHub Actions.
class AppConfig {
  static const owner = 'www774475437-svg';
  static const repo = 'ibn-alshabira';

  /// The website (GitHub Pages).
  static const siteUrl = 'https://$owner.github.io/$repo/';

  /// Always points to the newest APK.
  static const apkUrl = 'https://github.com/$owner/$repo/releases/latest/download/ibn-alshabira.apk';

  /// Store links — fill in once the app is published there.
  static const playStoreUrl = '';
  static const appStoreUrl = '';

  static const latestReleaseApi = 'https://api.github.com/repos/$owner/$repo/releases/latest';

  /// Set at build time: --dart-define=BUILD_NUMBER=<run number>.
  static const buildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

  static const version = '2.0.0';

  static String fatwaLink(String id) => '$siteUrl#/fatwa/$id';
}
