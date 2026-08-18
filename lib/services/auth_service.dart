import 'package:flutter/foundation.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

/// Microsoft 365 sign-in, built on Microsoft's own MSAL SDK — the same
/// engine the Office apps use. MSAL owns the browser handoff, redirect
/// capture, token cache, and silent refresh, which the generic OAuth
/// library kept fumbling.
///
/// Sign in once per device: MSAL caches the account in the keychain and
/// refreshes silently. Authorization stays server-side — being in the
/// tenant is not enough; the backend only accepts admins, allowlisted
/// users, and group members.
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  static const _tenantId = '40acb9f6-d0e3-4a23-9fc1-23e8e1ac0078';
  static const _clientId = 'cd8d142c-8a24-40f3-ac2e-7f2da60e2965';
  static const _authority = 'https://login.microsoftonline.com/$_tenantId';
  static const _redirectUri = 'msauth.com.charlestonlaw.insession.app://auth';

  // MSAL adds openid/profile/offline_access itself; only the API scope is
  // requested explicitly (reserved scopes in this list are an error on iOS).
  static const _scopes = ['api://$_clientId/access_as_user'];

  SingleAccountPca? _pca;
  String? _accessToken;
  Map<String, dynamic>? _me; // backend /me payload

  /// Human-readable reason the last sign-in step failed — shown in the UI so
  /// TestFlight users see the real error, never a silent spinner.
  String? lastError;

  bool get isSignedIn => _accessToken != null;
  Map<String, dynamic>? get me => _me;
  bool get isAdmin => _me?['isAdmin'] == true;
  bool get isAuthorized => _me?['authorized'] == true;
  List<Map<String, dynamic>> get groups =>
      List<Map<String, dynamic>>.from(_me?['groups'] ?? const []);

  Future<SingleAccountPca> _client() async {
    _pca ??= await SingleAccountPca.create(
      clientId: _clientId,
      appleConfig: AppleConfig(
        authority: _authority,
        authorityType: AuthorityType.aad,
        // Authenticator app when installed (one-tap SSO for staff who have
        // it), Safari otherwise.
        broker: Broker.msAuthenticator,
      ),
      androidConfig: AndroidConfig(
        configFilePath: 'assets/msal_config.json',
        redirectUri: _redirectUri,
      ),
    );
    return _pca!;
  }

  /// Restores a previous session silently. Hard-capped so a slow keychain or
  /// network can never hold the launch screen hostage.
  Future<bool> restoreSession() async {
    try {
      return await _restoreInner().timeout(const Duration(seconds: 12),
          onTimeout: () {
        debugPrint('🔐 restoreSession timed out');
        return false;
      });
    } catch (e) {
      debugPrint('🔐 restoreSession: no cached session ($e)');
      return false;
    }
  }

  Future<bool> _restoreInner() async {
    final pca = await _client();
    final result = await pca.acquireTokenSilent(scopes: _scopes);
    _accessToken = result.accessToken;
    return true;
  }

  /// Interactive Microsoft 365 sign-in.
  Future<bool> signIn() async {
    lastError = null;
    try {
      final pca = await _client();
      final result = await pca
          .acquireToken(scopes: _scopes, prompt: Prompt.selectAccount)
          .timeout(const Duration(seconds: 180), onTimeout: () {
        throw Exception('Timed out waiting for Microsoft sign-in to finish.');
      });
      _accessToken = result.accessToken;
      return true;
    } on MsalException catch (e) {
      lastError = _describeMsal(e);
      debugPrint('🔐 signIn failed: $lastError');
      return false;
    } catch (e) {
      lastError = _describe(e);
      debugPrint('🔐 signIn failed: $lastError');
      return false;
    }
  }

  String _describeMsal(MsalException e) {
    final text = e.message;
    final aadsts = RegExp(r'AADSTS\d+[^"\\]{0,200}').firstMatch(text);
    if (aadsts != null) return aadsts.group(0)!;
    if (e is MsalUserCancelException) return 'Sign-in was cancelled.';
    return text.length > 300 ? text.substring(0, 300) : text;
  }

  String _describe(Object e) {
    final text = e.toString();
    return text.length > 300 ? text.substring(0, 300) : text;
  }

  /// A valid bearer token, refreshed silently by MSAL when needed.
  Future<String?> bearerToken() async {
    try {
      final pca = await _client();
      final result = await pca
          .acquireTokenSilent(scopes: _scopes)
          .timeout(const Duration(seconds: 15));
      _accessToken = result.accessToken;
      return _accessToken;
    } catch (e) {
      debugPrint('🔐 silent token failed: $e');
      return _accessToken; // last known token as a fallback
    }
  }

  /// Fetches identity + groups from the backend. One retry with generous
  /// timeouts covers Function App cold starts.
  Future<Map<String, dynamic>?> fetchMe(Dio dio) async {
    final token = await bearerToken();
    if (token == null) return null;

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final sw = Stopwatch()..start();
        final response = await dio
            .get('/me',
                options: Options(headers: {'Authorization': 'Bearer $token'}))
            .timeout(const Duration(seconds: 25));
        debugPrint(
            '🔐 /me attempt $attempt: ${response.statusCode} in ${sw.elapsedMilliseconds}ms');
        if (response.statusCode == 200 && response.data is Map) {
          _me = Map<String, dynamic>.from(response.data);
          return _me;
        }
        return null;
      } catch (e) {
        debugPrint('🔐 /me attempt $attempt failed: $e');
        if (attempt == 2) {
          lastError = _describe(e);
          return null;
        }
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
    _me = null;
    try {
      final pca = await _client();
      await pca.signOut();
    } catch (e) {
      debugPrint('🔐 signOut: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_group_id');
    await prefs.remove('selected_group_name');
    await prefs.remove('signed_in_upn');
  }
}
