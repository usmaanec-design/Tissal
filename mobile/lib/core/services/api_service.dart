import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ApiService {
  static const String _prefServerHost = 'tisaal_server_host';
  static String? _customBaseUrl;

  static Future<void> loadSavedServerHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefServerHost);
      if (saved != null && saved.trim().isNotEmpty) {
        final scheme = saved.contains('trycloudflare') || saved.startsWith('https') ? 'https' : 'http';
        final clean = saved.trim().replaceAll('http://', '').replaceAll('https://', '').replaceAll('/api', '');
        _customBaseUrl = '$scheme://$clean/api';
      }
    } catch (_) {}
  }

  static Future<void> saveServerHost(String hostWithPort) async {
    final scheme = hostWithPort.contains('trycloudflare') || hostWithPort.startsWith('https') ? 'https' : 'http';
    final clean = hostWithPort.trim().replaceAll('http://', '').replaceAll('https://', '').replaceAll('/api', '');
    _customBaseUrl = '$scheme://$clean/api';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefServerHost, clean);
    } catch (_) {}
  }

  static String get serverHost {
    return baseUrl.replaceAll('http://', '').replaceAll('https://', '').replaceAll('/api', '');
  }

  static String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;
    if (kIsWeb && Uri.base.host.isNotEmpty && Uri.base.host != '0.0.0.0') {
      final scheme = Uri.base.scheme.startsWith('https') ? 'https' : 'http';
      if (Uri.base.host.contains('trycloudflare.com') || Uri.base.host.contains('onrender.com')) {
        return 'https://${Uri.base.host}/api';
      }
      final portPart = (Uri.base.port == 8080) ? ':4000' : (Uri.base.port != 80 && Uri.base.port != 443 ? ':${Uri.base.port}' : '');
      return '$scheme://${Uri.base.host}$portPart/api';
    }
    // 24/7 Cloud Production Server on Render:
    return 'https://tisaal-backend.onrender.com/api';
  }

  static set baseUrl(String url) {
    _customBaseUrl = url;
  }

  static String? authToken;

  static void setAuthToken(String? token) {
    authToken = token;
  }

  static void setServerHost(String hostWithPort) {
    saveServerHost(hostWithPort);
  }

  static Future<bool> testConnection(String hostWithPort) async {
    final scheme = hostWithPort.contains('trycloudflare') || hostWithPort.startsWith('https') ? 'https' : 'http';
    final clean = hostWithPort.trim().replaceAll('http://', '').replaceAll('https://', '').replaceAll('/api', '');
    try {
      final res = await http.get(Uri.parse('$scheme://$clean/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  /// Suggest auto username (e.g. MC-8KP39A)
  static Future<String> suggestUsername() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/auth/suggest-username'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['suggestedUsername'] as String;
      }
    } catch (e) {
      // Fallback local generator if offline
    }
    final rand = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'MC-${rand.substring(rand.length - 6)}';
  }

  /// Check if username is available
  static Future<bool> checkUsernameAvailable(String username) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/auth/check-username/$username'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['available'] == true;
      }
    } catch (_) {}
    return true;
  }

  /// Register new identity
  static Future<Map<String, dynamic>> register({
    required String username,
    required String publicKey,
    required String publicEncryptionKey,
    required String signature,
    String? displayName,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(),
      body: jsonEncode({
        'username': username,
        'publicKey': publicKey,
        'publicEncryptionKey': publicEncryptionKey,
        'displayName': displayName ?? username,
        'signature': signature,
      }),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 201) {
      return data;
    } else {
      throw Exception(data['error'] ?? 'Registration failed');
    }
  }

  /// Request auth challenge nonce
  static Future<String> requestChallenge(String accountId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/challenge'),
      headers: _headers(),
      body: jsonEncode({'accountId': accountId}),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 200) {
      return data['nonce'] as String;
    } else {
      throw Exception(data['error'] ?? 'Failed to request challenge nonce');
    }
  }

  /// Login / restore account using signed nonce
  static Future<Map<String, dynamic>> login({
    required String accountId,
    required String signature,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(),
      body: jsonEncode({
        'accountId': accountId,
        'signature': signature,
      }),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['error'] ?? 'Login failed');
    }
  }

  /// Search users by @username or accountId
  static Future<List<UserModel>> searchUsers(String query) async {
    final res = await http.get(
      Uri.parse('$baseUrl/users/search?q=${Uri.encodeComponent(query)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final list = data['results'] as List;
      return list.map((item) => UserModel.fromJson(item)).toList();
    }
    return [];
  }

  /// Get peer profile including public encryption key
  static Future<UserModel?> getPeerProfile(String accountId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/profile/$accountId'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return UserModel.fromJson(data['user']);
      }
    } catch (_) {}
    return null;
  }

  /// Fetch contacts list
  static Future<List<ContactModel>> getContacts() async {
    final res = await http.get(
      Uri.parse('$baseUrl/users/contacts'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final list = data['contacts'] as List;
      return list.map((item) => ContactModel.fromJson(item)).toList();
    }
    return [];
  }

  /// Send connection request to another user
  static Future<void> sendContactRequest(String targetAccountId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/users/contacts/request'),
      headers: _headers(),
      body: jsonEncode({'targetAccountId': targetAccountId}),
    );

    if (res.statusCode != 201) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to send contact request');
    }
  }

  /// Accept or reject contact request
  static Future<void> respondContactRequest(String contactId, String action) async {
    final res = await http.post(
      Uri.parse('$baseUrl/users/contacts/respond'),
      headers: _headers(),
      body: jsonEncode({'contactId': contactId, 'action': action}),
    );

    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to respond to request');
    }
  }

  /// Fetch message history between two users
  static Future<List<ChatMessageModel>> getMessages(String peerAccountId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/users/messages/$peerAccountId'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final list = data['messages'] as List;
      return list.map((item) => ChatMessageModel.fromJson(item)).toList();
    }
    return [];
  }

  /// Update public encryption key
  static Future<void> updateEncryptionKey(String publicEncryptionKey) async {
    try {
      await http.put(
        Uri.parse('$baseUrl/users/encryption-key'),
        headers: _headers(),
        body: jsonEncode({'publicEncryptionKey': publicEncryptionKey}),
      );
    } catch (_) {}
  }

  /// Send message via HTTP fallback
  static Future<bool> sendMessageHttp({
    required String targetAccountId,
    required String ephemeralPublicKey,
    required String nonce,
    required String ciphertext,
    required String authTag,
    String? tempId,
    String messageType = 'text',
    String? content,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/users/messages/send'),
        headers: _headers(),
        body: jsonEncode({
          'targetAccountId': targetAccountId,
          'ephemeralPublicKey': ephemeralPublicKey,
          'nonce': nonce,
          'ciphertext': ciphertext,
          'authTag': authTag,
          'tempId': tempId,
          'messageType': messageType,
          'content': content ?? '',
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Mark messages as read for peer
  static Future<bool> markMessagesAsRead(String peerAccountId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/users/messages/read'),
        headers: _headers(),
        body: jsonEncode({'peerAccountId': peerAccountId}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch user call logs
  static Future<List<CallLogModel>> getCallLogs() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/calls'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['calls'] as List;
        return list.map((item) => CallLogModel.fromJson(item)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Clear user call logs
  static Future<void> clearCallLogs() async {
    try {
      await http.delete(
        Uri.parse('$baseUrl/users/calls'),
        headers: _headers(),
      );
    } catch (_) {}
  }
}

