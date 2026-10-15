import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../core/services/api_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/websocket_service.dart';

class ChatProvider extends ChangeNotifier {
  List<ContactModel> _contacts = [];
  final Map<String, List<ChatMessageModel>> _conversations = {};
  final Set<String> _onlineAccountIds = {};
  final Map<String, String> _pinnedPeerEncryptionKeys = {};
  List<UserModel> _searchResults = [];
  bool _isLoading = false;

  StreamSubscription? _msgSubscription;
  StreamSubscription? _presenceSubscription;
  StreamSubscription? _contactSubscription;
  StreamSubscription? _ackSubscription;
  StreamSubscription? _readSubscription;
  Timer? _periodicSyncTimer;

  String _myAccountId = '';
  Uint8List? _myEncryptionSeed32;

  List<ContactModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  bool get isLoading => _isLoading;

  bool isUserOnline(String accountId) => _onlineAccountIds.contains(accountId);

  String? getPinnedEncryptionKey(String peerAccountId) => _pinnedPeerEncryptionKeys[peerAccountId];

  bool verifyOrUpdatePeerEncryptionKey(String peerAccountId, String newKey) {
    if (newKey.isEmpty) return true;
    final existing = _pinnedPeerEncryptionKeys[peerAccountId];
    if (existing == null) {
      _pinnedPeerEncryptionKeys[peerAccountId] = newKey;
      return true;
    }
    if (existing != newKey) {
      return false; // Key changed!
    }
    return true;
  }

  void pinPeerEncryptionKey(String peerAccountId, String key) {
    _pinnedPeerEncryptionKeys[peerAccountId] = key;
  }

  List<ChatMessageModel> getMessagesForUser(String peerAccountId) {
    return _conversations[peerAccountId] ?? [];
  }

  Set<String> get conversationPeerIds => _conversations.keys.toSet();
  Map<String, List<ChatMessageModel>> get conversations => _conversations;

  void setMyIdentity(CryptoIdentity identity) {
    _myAccountId = identity.accountId;
    _myEncryptionSeed32 = identity.encryptionSeed32;
  }

  void setMyAccountId(String accountId) {
    _myAccountId = accountId;
  }

  void initSubscriptions() {
    _msgSubscription?.cancel();
    _presenceSubscription?.cancel();
    _contactSubscription?.cancel();
    _ackSubscription?.cancel();
    _readSubscription?.cancel();
    _periodicSyncTimer?.cancel();

    // 1. Incoming Message stream
    _msgSubscription = WebSocketService().onMessage.listen((message) async {
      await _handleIncomingMessage(message);
    });

    // 2. Chat ACK stream (updates tempId to real DB id and delivery status)
    _ackSubscription = WebSocketService().onChatAck.listen((ack) {
      final tempId = ack['tempId'] as String?;
      final realId = ack['id'] as String?;
      final delivered = ack['delivered'] == true;
      if (tempId != null && realId != null) {
        for (final entry in _conversations.entries) {
          final list = entry.value;
          final idx = list.indexWhere((m) => m.id == tempId);
          if (idx >= 0) {
            list[idx] = list[idx].copyWith(id: realId, isDelivered: delivered);
            _persistConversation(entry.key);
            notifyListeners();
            break;
          }
        }
      }
    });

    // 3. Read receipt stream (turns ticks blue on sender device)
    _readSubscription = WebSocketService().onReadReceipt.listen((event) {
      final readerId = event['readerAccountId'] as String?;
      if (readerId != null && _conversations.containsKey(readerId)) {
        final list = _conversations[readerId]!;
        bool changed = false;
        for (int i = 0; i < list.length; i++) {
          if (list[i].senderAccountId == _myAccountId && !list[i].isRead) {
            list[i] = list[i].copyWith(isRead: true, isDelivered: true);
            changed = true;
          }
        }
        if (changed) {
          _persistConversation(readerId);
          notifyListeners();
        }
      }
    });

    // 4. Online Presence stream
    _presenceSubscription = WebSocketService().onPresence.listen((event) {
      if (event['type'] == 'presence:init') {
        final ids = (event['onlineAccountIds'] as List<dynamic>?)?.map((e) => e.toString()) ?? [];
        _onlineAccountIds.clear();
        _onlineAccountIds.addAll(ids);
        notifyListeners();
        return;
      }

      final accountId = event['accountId'] as String?;
      final isOnline = event['isOnline'] == true;
      if (accountId != null) {
        if (isOnline) {
          _onlineAccountIds.add(accountId);
        } else {
          _onlineAccountIds.remove(accountId);
        }
        notifyListeners();
      }
    });

    // 5. Contact Update stream
    _contactSubscription = WebSocketService().onContactUpdate.listen((_) {
      loadContacts(silent: true);
      NotificationService.showInApp(
        title: 'Contact Update',
        message: 'A contact request or status update was received.',
        icon: Icons.person_add_rounded,
      );
    });

    loadContacts();

    // Lightweight sync timer (every 15s instead of aggressive 4s)
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      loadContacts(silent: true);
    });
  }

  Future<void> _handleIncomingMessage(ChatMessageModel message) async {
    String messageContent = message.content;

    // If message is encrypted with AEAD ciphertext
    if (message.ciphertext.isNotEmpty && _myEncryptionSeed32 != null) {
      try {
        final envelope = EncryptedEnvelope(
          ephemeralPublicKeyHex: message.ephemeralPublicKey,
          nonceHex: message.nonce,
          ciphertextHex: message.ciphertext,
          authTagHex: message.authTag,
        );
        messageContent = await CryptoService.decryptPayload(
          envelope: envelope,
          recipientEncryptionSeed32: _myEncryptionSeed32!,
          senderAccountId: message.senderAccountId,
          recipientAccountId: message.receiverAccountId,
        );
      } catch (err) {
        messageContent = '[E2EE Message: Authentication Tag Verification Failed]';
      }
    }

    final finalMsg = message.copyWith(content: messageContent);
    _addMessage(finalMsg);

    // Save immediately to local persistent storage
    final peerId = finalMsg.senderAccountId == _myAccountId
        ? finalMsg.receiverAccountId
        : finalMsg.senderAccountId;
    _persistConversation(peerId);

    // Show system notification and in-app pill banner
    NotificationService.showMessageNotification(
      senderName: message.senderAccountId.length > 8
          ? message.senderAccountId.substring(0, 8)
          : message.senderAccountId,
      message: messageContent,
    );

    NotificationService.showInApp(
      title: 'New Message',
      message: messageContent,
      icon: Icons.chat_bubble_outline_rounded,
    );
  }

  Future<void> loadContacts({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _contacts = await ApiService.getContacts();
    } catch (_) {}

    if (!silent) {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _searchResults = await ApiService.searchUsers(query);
    } catch (_) {
      _searchResults = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendContactRequest(String targetAccountId) async {
    await ApiService.sendContactRequest(targetAccountId);
    await loadContacts();
  }

  Future<void> respondToContact(String contactId, String action) async {
    await ApiService.respondContactRequest(contactId, action);
    await loadContacts();
  }

  /// Mark all messages in a conversation as read by the user
  Future<void> markConversationAsRead(String peerAccountId) async {
    if (!_conversations.containsKey(peerAccountId)) return;
    final list = _conversations[peerAccountId]!;
    bool changed = false;

    for (int i = 0; i < list.length; i++) {
      if (list[i].receiverAccountId == _myAccountId && !list[i].isRead) {
        list[i] = list[i].copyWith(isRead: true);
        changed = true;
      }
    }

    if (changed) {
      _persistConversation(peerAccountId);
      notifyListeners();
    }

    // Send read receipt to server and peer
    WebSocketService().sendReadReceipt(peerAccountId);
    ApiService.markMessagesAsRead(peerAccountId);
  }

  /// Load messages with local storage cache first, then sync new messages
  Future<void> loadMessages(String peerAccountId) async {
    // 1. Immediately load local persisted messages so screen is never blank
    await loadPersistedMessages(peerAccountId);

    try {
      // 2. Fetch messages from server
      final messages = await ApiService.getMessages(peerAccountId);
      final existingList = _conversations[peerAccountId] ?? [];

      // Create a lookup of already decrypted messages by ID or nonce
      final Map<String, String> decryptedCache = {};
      for (final m in existingList) {
        if (m.content.isNotEmpty) {
          decryptedCache[m.id] = m.content;
          if (m.nonce.isNotEmpty) {
            decryptedCache[m.nonce] = m.content;
          }
        }
      }

      final decryptedList = <ChatMessageModel>[];

      for (final msg in messages) {
        // Reuse cached plaintext if already decrypted (avoids re-running expensive cryptography)
        if (decryptedCache.containsKey(msg.id)) {
          decryptedList.add(msg.copyWith(content: decryptedCache[msg.id]));
          continue;
        }
        if (msg.nonce.isNotEmpty && decryptedCache.containsKey(msg.nonce)) {
          decryptedList.add(msg.copyWith(content: decryptedCache[msg.nonce]));
          continue;
        }

        if (msg.ciphertext.isNotEmpty &&
            msg.receiverAccountId == _myAccountId &&
            _myEncryptionSeed32 != null) {
          try {
            final envelope = EncryptedEnvelope(
              ephemeralPublicKeyHex: msg.ephemeralPublicKey,
              nonceHex: msg.nonce,
              ciphertextHex: msg.ciphertext,
              authTagHex: msg.authTag,
            );
            final decrypted = await CryptoService.decryptPayload(
              envelope: envelope,
              recipientEncryptionSeed32: _myEncryptionSeed32!,
              senderAccountId: msg.senderAccountId,
              recipientAccountId: msg.receiverAccountId,
            );
            decryptedList.add(msg.copyWith(content: decrypted));
          } catch (_) {
            decryptedList.add(msg.copyWith(content: '[Decryption Error: Invalid Key or Tag]'));
          }
        } else if (msg.senderAccountId == _myAccountId) {
          // Check if we have our sent message in local cache
          String text = msg.content;
          if (text.isEmpty) {
            final match = existingList.firstWhere(
              (m) => m.id == msg.id || (m.senderAccountId == _myAccountId && m.content.isNotEmpty),
              orElse: () => msg,
            );
            if (match.content.isNotEmpty) {
              text = match.content;
            }
          }
          decryptedList.add(msg.copyWith(content: text));
        } else {
          decryptedList.add(msg);
        }
      }

      // Preserve any pending local messages not yet returned by the server
      for (final local in existingList) {
        if (local.senderAccountId == _myAccountId &&
            !decryptedList.any((m) => m.id == local.id)) {
          decryptedList.add(local);
        }
      }

      decryptedList.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _conversations[peerAccountId] = decryptedList;
      _persistConversation(peerAccountId);
      notifyListeners();
    } catch (_) {}
  }

  /// Send message cleanly with zero duplicate sends
  Future<void> sendMessage({
    required String myAccountId,
    required String peerAccountId,
    required String content,
    String? recipientPublicEncryptionKey,
  }) async {
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) return;

    final tempId = const Uuid().v4();
    final convId = ([myAccountId, peerAccountId]..sort()).join(':');

    // Display immediately in sender UI in plaintext
    final localMsg = ChatMessageModel(
      id: tempId,
      conversationId: convId,
      senderAccountId: myAccountId,
      receiverAccountId: peerAccountId,
      content: cleanContent,
      createdAt: DateTime.now(),
      isDelivered: false,
      isRead: false,
    );

    _addMessage(localMsg);
    _persistConversation(peerAccountId);

    // If recipient has an X25519 public encryption key, encrypt via ChaCha20-Poly1305 AEAD
    if (recipientPublicEncryptionKey != null && recipientPublicEncryptionKey.isNotEmpty) {
      final keyMatches = verifyOrUpdatePeerEncryptionKey(peerAccountId, recipientPublicEncryptionKey);
      if (!keyMatches) {
        final alertMsg = ChatMessageModel(
          id: const Uuid().v4(),
          conversationId: convId,
          senderAccountId: 'system',
          receiverAccountId: myAccountId,
          content: '⚠️ Security Notice: The recipient identity encryption key has changed since your last conversation.',
          createdAt: DateTime.now(),
          isDelivered: true,
          isRead: true,
        );
        _addMessage(alertMsg);
        pinPeerEncryptionKey(peerAccountId, recipientPublicEncryptionKey);
      }

      try {
        final envelope = await CryptoService.encryptPayload(
          recipientPublicEncryptionKeyHex: recipientPublicEncryptionKey,
          plaintext: cleanContent,
          senderAccountId: myAccountId,
          recipientAccountId: peerAccountId,
        );

        if (WebSocketService().isConnected) {
          WebSocketService().sendEncryptedMessage(
            targetAccountId: peerAccountId,
            ephemeralPublicKey: envelope.ephemeralPublicKeyHex,
            nonce: envelope.nonceHex,
            ciphertext: envelope.ciphertextHex,
            authTag: envelope.authTagHex,
            tempId: tempId,
          );
        } else {
          // Send via HTTP fallback only if WebSocket is disconnected
          await ApiService.sendMessageHttp(
            targetAccountId: peerAccountId,
            ephemeralPublicKey: envelope.ephemeralPublicKeyHex,
            nonce: envelope.nonceHex,
            ciphertext: envelope.ciphertextHex,
            authTag: envelope.authTagHex,
            tempId: tempId,
          );
        }
        return;
      } catch (err) {
        debugPrint('[ChatProvider] Encryption error: $err');
      }
    }

    // Fallback unencrypted message if peer has no key yet
    if (WebSocketService().isConnected) {
      WebSocketService().sendChatMessage(
        targetAccountId: peerAccountId,
        content: cleanContent,
        tempId: tempId,
      );
    } else {
      await ApiService.sendMessageHttp(
        targetAccountId: peerAccountId,
        ephemeralPublicKey: '',
        nonce: '',
        ciphertext: '',
        authTag: '',
        tempId: tempId,
        content: cleanContent,
      );
    }
  }

  void _addMessage(ChatMessageModel msg) {
    final peerId = msg.senderAccountId == msg.receiverAccountId
        ? msg.senderAccountId
        : (msg.senderAccountId == _myAccountId ? msg.receiverAccountId : msg.senderAccountId);

    if (!_conversations.containsKey(peerId)) {
      _conversations[peerId] = [];
    }

    final list = _conversations[peerId]!;
    final existingIdx = list.indexWhere((m) => m.id == msg.id);
    if (existingIdx >= 0) {
      list[existingIdx] = msg;
    } else {
      list.add(msg);
    }

    notifyListeners();
  }

  // --- Local Persistence via SharedPreferences ---

  String _getStorageKey(String peerAccountId) => 'chat_msgs_${_myAccountId}_$peerAccountId';

  Future<void> _persistConversation(String peerAccountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _conversations[peerAccountId] ?? [];
      final encoded = jsonEncode(list.map((m) => m.toJson()).toList());
      await prefs.setString(_getStorageKey(peerAccountId), encoded);
    } catch (_) {}
  }

  Future<void> loadPersistedMessages(String peerAccountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_getStorageKey(peerAccountId));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final loaded = decoded.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
        if (loaded.isNotEmpty) {
          _conversations[peerAccountId] = loaded;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// Explicitly delete conversation (only when user chooses to delete)
  Future<void> deleteConversation(String peerAccountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getStorageKey(peerAccountId));
      _conversations.remove(peerAccountId);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _ackSubscription?.cancel();
    _readSubscription?.cancel();
    _presenceSubscription?.cancel();
    _contactSubscription?.cancel();
    _periodicSyncTimer?.cancel();
    super.dispose();
  }
}
