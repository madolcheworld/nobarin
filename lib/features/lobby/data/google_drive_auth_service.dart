import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/google_drive_account.dart';

/// Service managing Google Sign-In and OAuth token for Google Drive integration.
class GoogleDriveAuthService extends ChangeNotifier {
  static GoogleDriveAuthService? _instance;
  static GoogleDriveAuthService get instance =>
      _instance ??= GoogleDriveAuthService();

  static const String _accountPrefsKey = 'cached_google_drive_account';

  static const List<String> driveScopes = [
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/drive.file',
  ];

  final GoogleSignIn _googleSignIn;
  GoogleDriveAccount? _currentAccount;
  bool _isLoading = false;
  String? _errorMessage;

  GoogleDriveAuthService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: driveScopes);

  GoogleDriveAccount? get currentAccount => _currentAccount;
  bool get isSignedIn => _currentAccount != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initializes auth service from local cache and attempts silent sign-in
  Future<void> init({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final savedStr = p.getString(_accountPrefsKey);
      if (savedStr != null && savedStr.isNotEmpty) {
        final data = jsonDecode(savedStr) as Map<String, dynamic>;
        _currentAccount = GoogleDriveAccount.fromMap(data);
        notifyListeners();
      }

      // If user was signed in with real Google account, attempt silent refresh
      if (_currentAccount != null && !_currentAccount!.isMock) {
        try {
          final account = await _googleSignIn.signInSilently();
          if (account != null) {
            final auth = await account.authentication;
            _currentAccount = GoogleDriveAccount.fromGoogleSignIn(
              id: account.id,
              email: account.email,
              displayName: account.displayName ?? account.email.split('@').first,
              photoUrl: account.photoUrl,
              accessToken: auth.accessToken,
            );
            await p.setString(_accountPrefsKey, _currentAccount!.toJson());
            notifyListeners();
          }
        } catch (e) {
          debugPrint('[GoogleDriveAuthService] silent sign-in note: $e');
        }
      }
    } catch (e) {
      debugPrint('[GoogleDriveAuthService] init error: $e');
    }
  }

  /// Interactive Sign-In with Google or simulated Demo account
  Future<GoogleDriveAccount?> signIn({bool forceMock = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (forceMock) {
        final mock = GoogleDriveAccount.mockDemo();
        _currentAccount = mock;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_accountPrefsKey, mock.toJson());
        _isLoading = false;
        notifyListeners();
        return mock;
      }

      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User aborted the sign-in modal
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final auth = await account.authentication;
      final newAccount = GoogleDriveAccount.fromGoogleSignIn(
        id: account.id,
        email: account.email,
        displayName: account.displayName ?? account.email.split('@').first,
        photoUrl: account.photoUrl,
        accessToken: auth.accessToken,
      );

      _currentAccount = newAccount;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountPrefsKey, newAccount.toJson());

      _isLoading = false;
      notifyListeners();
      return newAccount;
    } catch (e) {
      debugPrint('[GoogleDriveAuthService] signIn error: $e');
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Sign out from Google account and remove cached credentials
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_currentAccount != null && !_currentAccount!.isMock) {
        await _googleSignIn.signOut();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accountPrefsKey);
      _currentAccount = null;
    } catch (e) {
      debugPrint('[GoogleDriveAuthService] signOut error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Retrieve active access token or null
  Future<String?> getValidAccessToken() async {
    if (_currentAccount == null) return null;
    if (_currentAccount!.isMock) return _currentAccount!.accessToken;

    try {
      final account = _googleSignIn.currentUser;
      if (account != null) {
        final auth = await account.authentication;
        return auth.accessToken;
      }
    } catch (_) {}
    return _currentAccount?.accessToken;
  }
}
