import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../core/services/api_service.dart';
import '../core/services/websocket_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  CryptoIdentity? _identity;
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  CryptoIdentity? get identity => _identity;
  String? get token => _token;
  bool get isAuthenticated => _currentUser != null && _token != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  static const String _prefMnemonic = 'tisaal_mnemonic';
  static const String _prefToken = 'tisaal_token';
  static const String _prefUsername = 'tisaal_username';
  static const String _prefAccountId = 'tisaal_account_id';
  static const String _prefDisplayName = 'tisaal_display_name';
  static const String _prefPublicKey = 'tisaal_public_key';
  static const String _prefPublicEncryptionKey = 'tisaal_public_encryption_key';

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await ApiService.loadSavedServerHost();
      final prefs = await SharedPreferences.getInstance();
      final savedMnemonic = prefs.getString(_prefMnemonic);
      final savedToken = prefs.getString(_prefToken);
      final savedUsername = prefs.getString(_prefUsername);
      final savedAccountId = prefs.getString(_prefAccountId);
      final savedDisplayName = prefs.getString(_prefDisplayName);
      final savedPublicKey = prefs.getString(_prefPublicKey);
      final savedPublicEncryptionKey = prefs.getString(_prefPublicEncryptionKey);

      if (savedMnemonic != null &&
          savedToken != null &&
          savedUsername != null &&
          savedAccountId != null) {
        _identity = await CryptoService.deriveIdentityFromMnemonicAsync(savedMnemonic);
        _token = savedToken;
        _currentUser = UserModel(
          accountId: savedAccountId,
          username: savedUsername,
          displayName: savedDisplayName ?? savedUsername,
          publicKey: savedPublicKey ?? _identity!.publicKeyHex,
          publicEncryptionKey: savedPublicEncryptionKey ?? _identity!.publicEncryptionKeyHex,
        );

        ApiService.setAuthToken(_token);
        _connectWebSocket();

        // Auto-heal: Ensure backend has the canonical X25519 public encryption key
        if (_identity != null) {
          ApiService.updateEncryptionKey(_identity!.publicEncryptionKeyHex);
          await prefs.setString(_prefPublicEncryptionKey, _identity!.publicEncryptionKeyHex);
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create brand new account with generated mnemonic
  Future<CryptoIdentity> createAccount({
    required String username,
    String? displayName,
    CryptoIdentity? pregeneratedIdentity,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final identity = pregeneratedIdentity != null
          ? await CryptoService.deriveIdentityFromMnemonicAsync(pregeneratedIdentity.mnemonic)
          : await CryptoService.generateNewIdentityAsync();
      final cleanUsername = username.trim().startsWith('@')
          ? username.trim().substring(1)
          : username.trim();

      // Sign the registration message including both identity signing key and X25519 encryption key
      final registrationMessage = 'register:$cleanUsername:${identity.publicKeyHex}:${identity.publicEncryptionKeyHex}';
      final signature = CryptoService.signMessage(identity.privateKey, registrationMessage);

      final res = await ApiService.register(
        username: cleanUsername,
        publicKey: identity.publicKeyHex,
        publicEncryptionKey: identity.publicEncryptionKeyHex,
        displayName: displayName ?? cleanUsername,
        signature: signature,
      );

      _token = res['token'] as String;
      _identity = identity;
      _currentUser = UserModel.fromJson(res['user']);

      ApiService.setAuthToken(_token);
      await _saveSessionToPrefs();
      _connectWebSocket();

      return identity;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Restore account from 12-word recovery phrase
  Future<void> restoreAccount(String mnemonic) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final identity = await CryptoService.deriveIdentityFromMnemonicAsync(mnemonic);
      
      // Request challenge nonce from backend
      final nonce = await ApiService.requestChallenge(identity.accountId);
      
      // Sign nonce with derived Ed25519 private key
      final signature = CryptoService.signMessage(identity.privateKey, nonce);

      final res = await ApiService.login(
        accountId: identity.accountId,
        signature: signature,
      );

      _token = res['token'] as String;
      _identity = identity;
      _currentUser = UserModel.fromJson(res['user']);

      ApiService.setAuthToken(_token);
      await _saveSessionToPrefs();
      _connectWebSocket();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveSessionToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_identity != null) {
      await prefs.setString(_prefMnemonic, _identity!.mnemonic);
      await prefs.setString(_prefPublicKey, _identity!.publicKeyHex);
      await prefs.setString(_prefPublicEncryptionKey, _identity!.publicEncryptionKeyHex);
    }
    if (_token != null) {
      await prefs.setString(_prefToken, _token!);
    }
    if (_currentUser != null) {
      await prefs.setString(_prefUsername, _currentUser!.username);
      await prefs.setString(_prefAccountId, _currentUser!.accountId);
      await prefs.setString(_prefDisplayName, _currentUser!.displayName);
    }
  }

  void _connectWebSocket() {
    if (_token != null) {
      final wsUrl = ApiService.baseUrl.startsWith('https')
          ? ApiService.baseUrl.replaceFirst('https', 'wss').replaceFirst('/api', '/ws')
          : ApiService.baseUrl.replaceFirst('http', 'ws').replaceFirst('/api', '/ws');
      WebSocketService().connect(wsUrl, _token!);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    WebSocketService().disconnect();
    ApiService.setAuthToken(null);
    _currentUser = null;
    _identity = null;
    _token = null;
    notifyListeners();
  }
}
