import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

/// Microsoft 365 sign-in for the scanner.
///
/// Sign in once: tokens live in the keychain and refresh silently, and the
/// chosen group is remembered, so staff see the login screen exactly once per
/// device. Authorization is enforced server-side — being in the tenant is not
/// enough; the backend only accepts admins, allowlisted users, and group
/// members.
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  static const _tenantId = '40acb9f6-d0e3-4a23-9fc1-23e8e1ac0078';
  static const _clientId = 'cd8d142c-8a24-40f3-ac2e-7f2da60e2965';
  static const _redirectUrl = 'msauth.com.charlestonlaw.insession.app://auth';
  static const _apiScope = 'api://$_clientId/access_as_user';
  static const _issuerBase =
      'https://login.microsoftonline.com/$_tenantId/oauth2/v2.0';

  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  DateTime? _accessTokenExpiry;
  Map<String, dynamic>? _me; // backend /me payload

  bool get isSignedIn => _accessToken != null;
  Map<String, dynamic>? get me => _me;
  bool get isAdmin => _me?['isAdmin'] == true;
  bool get isAuthorized => _me?['authorized'] == true;
  List<Map<String, dynamic>> get groups =>
      List<Map<String, dynamic>>.from(_me?['groups'] ?? const []);

  static const _serviceConfig = AuthorizationServiceConfiguration(
    authorizationEndpoint: '$_issuerBase/authorize',
    tokenEndpoint: '$_issuerBase/token',
  );

  static const _scopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
    _apiScope,
  ];

  /// Attempts to restore a previous session without any UI.
  /// Hard-capped: a slow keychain or token endpoint must never hold the
  /// launch screen hostage.
  Future<bool> restoreSession() async {
    try {
      return await _restoreSessionInner()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('🔐 restoreSession timed out');
        return false;
      });
    } catch (e) {
      debugPrint('🔐 restoreSession failed: $e');
      return false;
    }
  }

  Future<bool> _restoreSessionInner() async {
    final refreshToken = await _storage.read(key: 'ms_refresh_token');
    if (refreshToken == null) return false;
    return await _refresh(refreshToken);
  }

  /// Interactive Microsoft 365 sign-in.
  Future<bool> signIn() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirectUrl,
          serviceConfiguration: _serviceConfig,
          scopes: _scopes,
          promptValues: const ['select_account'],
        ),
      );
      await _storeTokens(result.accessToken, result.refreshToken,
          result.accessTokenExpirationDateTime);
      return _accessToken != null;
    } catch (e) {
      debugPrint('🔐 signIn failed or was cancelled: $e');
      return false;
    }
  }

  Future<bool> _refresh(String refreshToken) async {
    try {
      final result = await _appAuth.token(TokenRequest(
        _clientId,
        _redirectUrl,
        serviceConfiguration: _serviceConfig,
        refreshToken: refreshToken,
        scopes: _scopes,
      ));
      await _storeTokens(result.accessToken, result.refreshToken,
          result.accessTokenExpirationDateTime);
      return _accessToken != null;
    } catch (e) {
      debugPrint('🔐 token refresh failed: $e');
      return false;
    }
  }

  Future<void> _storeTokens(
      String? access, String? refresh, DateTime? expiry) async {
    _accessToken = access;
    _accessTokenExpiry = expiry;
    if (refresh != null) {
      await _storage.write(key: 'ms_refresh_token', value: refresh);
    }
  }

  /// A valid bearer token, silently refreshed when close to expiry.
  Future<String?> bearerToken() async {
    if (_accessToken != null &&
        _accessTokenExpiry != null &&
        _accessTokenExpiry!
            .isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return _accessToken;
    }
    final refreshToken = await _storage.read(key: 'ms_refresh_token');
    if (refreshToken != null && await _refresh(refreshToken)) {
      return _accessToken;
    }
    return _accessToken;
  }

  /// Fetches identity + groups from the backend. Requires a signed-in user.
  ///
  /// The Function App scales to zero, so the first call after idle can take
  /// several seconds — one retry with generous timeouts covers cold starts
  /// without ever spinning forever.
  Future<Map<String, dynamic>?> fetchMe(Dio dio) async {
    final token = await bearerToken()
        .timeout(const Duration(seconds: 10), onTimeout: () => _accessToken);
    if (token == null) return null;

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final sw = Stopwatch()..start();
        final response = await dio
            .get('/me',
                options: Options(headers: {'Authorization': 'Bearer $token'}))
            .timeout(const Duration(seconds: 25));
        debugPrint('🔐 /me attempt $attempt: ${response.statusCode} in ${sw.elapsedMilliseconds}ms');
        if (response.statusCode == 200 && response.data is Map) {
          _me = Map<String, dynamic>.from(response.data);
          return _me;
        }
        return null;
      } catch (e) {
        debugPrint('🔐 /me attempt $attempt failed: $e');
        if (attempt == 2) return null;
      }
    }
    return null;
  }

  // ---- remembered group selection ----

  Future<String?> selectedGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_group_id');
  }

  Future<Map<String, dynamic>?> selectedGroup() async {
    final id = await selectedGroupId();
    if (id == null) return null;
    try {
      return groups.firstWhere((g) => g['id'] == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> selectGroup(String groupId, String groupName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_group_id', groupId);
    await prefs.setString('selected_group_name', groupName);
  }

  Future<void> signOut() async {
    _accessToken = null;
    _accessTokenExpiry = null;
    _me = null;
    await _storage.delete(key: 'ms_refresh_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_group_id');
    await prefs.remove('selected_group_name');
  }

  /// Debug helper: decoded claims of the current token.
  Map<String, dynamic>? get tokenClaims {
    final t = _accessToken;
    if (t == null) return null;
    try {
      final payload = t.split('.')[1];
      final normalized = base64Url.normalize(payload);
      return jsonDecode(utf8.decode(base64Url.decode(normalized)));
    } catch (_) {
      return null;
    }
  }
}
