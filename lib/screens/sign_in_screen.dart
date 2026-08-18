import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/group_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/theme.dart';
import 'home_screen.dart';

/// Gate shown until the user has signed in with Microsoft 365 and picked
/// their group. Both are remembered, so this appears once per device.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = true;
  String _version = '';
  String _busyLabel = 'Checking for a saved session…';
  String? _error;
  List<Map<String, dynamic>> _groupsToPick = const [];

  Dio get _dio => Dio(BaseOptions(
        baseUrl: 'https://insession-api-fc.azurewebsites.net',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ));

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version} (${info.buildNumber})');
    });
    _tryRestore();
  }

  Future<void> _tryRestore() async {
    final auth = AuthService.instance;
    if (await auth.restoreSession()) {
      await _afterSignIn();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _busyLabel = 'Signing in with Microsoft 365…';
      _error = null;
    });
    final ok = await AuthService.instance.signIn();
    if (!ok) {
      final detail = AuthService.instance.lastError;
      setState(() {
        _busy = false;
        _error = detail == null || detail.isEmpty
            ? 'Sign-in was cancelled or failed. Please try again.'
            : 'Sign-in failed:\n$detail';
      });
      return;
    }
    await _afterSignIn();
  }

  Future<void> _afterSignIn() async {
    final auth = AuthService.instance;
    if (mounted) {
      setState(() {
        _busy = true;
        _busyLabel = 'Contacting the server…\n(first call can take a few seconds)';
      });
    }
    final me = await auth.fetchMe(_dio);

    if (me == null) {
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
      return;
    }

    // Remember who signed in, for the account menu and mode selection.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('signed_in_upn', me['upn']?.toString() ?? '');
    GroupSession.upn = me['upn']?.toString();

    if (me['authorized'] != true) {
      await auth.signOut();
      setState(() {
        _busy = false;
        _error =
            'Your account (${me['upn']}) is signed in but not authorized for '
            'inSession. Ask an administrator for a group invite.';
      });
      return;
    }

    // Group selection: remembered choice wins; a single group auto-selects;
    // multiple groups ask once.
    final remembered = await auth.selectedGroup();
    final groups = auth.groups;
    if (remembered != null || groups.isEmpty) {
      _enterApp();
      return;
    }
    if (groups.length == 1) {
      await auth.selectGroup(groups.first['id'], groups.first['name']);
      await GroupSession.load();
      _enterApp();
      return;
    }
    setState(() {
      _busy = false;
      _groupsToPick = groups;
    });
  }

  Future<void> _pickGroup(Map<String, dynamic> group) async {
    await AuthService.instance.selectGroup(group['id'], group['name']);
    await GroupSession.load();
    _enterApp();
  }

  void _enterApp() {
    if (!mounted) return;
    // Make the API client aware of the signed-in user before entering.
    FirebaseService.instance.attachAuth(AuthService.instance);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _busy
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(_busyLabel,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 28),
                      // Escape hatch even mid-handshake: the device key still
                      // authenticates, so a slow server never blocks scanning.
                      TextButton(
                        onPressed: _enterApp,
                        child: const Text('Continue without signing in'),
                      ),
                    ],
                  )
                : _groupsToPick.isNotEmpty
                    ? _groupPicker()
                    : _signInView(),
          ),
        ),
      ),
    );
  }

  Widget _signInView() {
    // Branding floats in the upper half; actions sit low, in thumb range.
    return Column(
      children: [
        const Spacer(flex: 3),
        const Icon(Icons.qr_code_scanner, size: 72, color: AppTheme.navy),
        const SizedBox(height: 16),
        Text('InSession',
            style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        Text('Charleston School of Law',
            style: Theme.of(context).textTheme.bodyLarge),
        const Spacer(flex: 4),
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.errorRed, fontSize: 15),
          ),
          const SizedBox(height: 20),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.workspaces_outline),
            label: const Text('Sign in with Microsoft 365'),
          ),
        ),
        const SizedBox(height: 8),
        // Transition escape hatch: the shared device key still authenticates,
        // so staff are never stranded at a login screen mid-event. Remove once
        // every device has signed in.
        TextButton(
          onPressed: _enterApp,
          child: const Text('Continue without signing in'),
        ),
        Text(_version,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _groupPicker() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Select your group',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('Remembered on this device — change it later from Settings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 32),
        ..._groupsToPick.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _pickGroup(g),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(g['name'] ?? 'Group',
                        style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}
