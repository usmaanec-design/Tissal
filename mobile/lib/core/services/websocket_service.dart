import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

typedef MessageCallback = void Function(ChatMessageModel message);
typedef CallEventCallback = void Function(Map<String, dynamic> event);
typedef PresenceCallback = void Function(String accountId, bool isOnline);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  final StreamController<ChatMessageModel> _messageController =
      StreamController<ChatMessageModel>.broadcast();
  final StreamController<Map<String, dynamic>> _callEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _contactController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _ackController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _readReceiptController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<ChatMessageModel> get onMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onCallEvent => _callEventController.stream;
  Stream<Map<String, dynamic>> get onPresence => _presenceController.stream;
  Stream<Map<String, dynamic>> get onContactUpdate => _contactController.stream;
  Stream<Map<String, dynamic>> get onChatAck => _ackController.stream;
  Stream<Map<String, dynamic>> get onReadReceipt => _readReceiptController.stream;

  bool get isConnected => _isConnected;

  String? _lastWsUrl;
  String? _lastToken;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  Future<void> connect(String wsUrl, String token) async {
    _lastWsUrl = wsUrl;
    _lastToken = token;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    disconnect(cleanSession: false);

    try {
      final uri = Uri.parse('$wsUrl?token=$token');
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;

      _subscription = _channel!.stream.listen(
        (data) {
          _handleIncoming(data);
        },
        onError: (err) {
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
      );

      // Send explicit auth:init to ensure connection is registered across all web environments
      send({'type': 'auth:init', 'token': token});

      // Keep connection alive with periodic heartbeat
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_isConnected) {
          send({'type': 'ping'});
        }
      });
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_lastWsUrl == null || _lastToken == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!_isConnected && _lastWsUrl != null && _lastToken != null) {
        connect(_lastWsUrl!, _lastToken!);
      }
    });
  }

  void _handleIncoming(dynamic rawData) {
    try {
      final map = jsonDecode(rawData.toString()) as Map<String, dynamic>;
      final type = map['type'] as String?;

      if (type == 'chat:received') {
        final message = ChatMessageModel.fromJson(map);
        _messageController.add(message);
      } else if (type == 'chat:ack') {
        _ackController.add(map);
      } else if (type == 'chat:read') {
        _readReceiptController.add(map);
      } else if (type != null &&
          (type.startsWith('call:') || type.startsWith('webrtc:'))) {
        _callEventController.add(map);
      } else if (type == 'presence:update' || type == 'presence:init') {
        _presenceController.add(map);
      } else if (type == 'contact:updated') {
        _contactController.add(map);
      }
    } catch (e) {
      // ignore parse error
    }
  }

  void send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (_) {
        _isConnected = false;
        _scheduleReconnect();
      }
    } else {
      _scheduleReconnect();
    }
  }

  void sendEncryptedMessage({
    required String targetAccountId,
    required String ephemeralPublicKey,
    required String nonce,
    required String ciphertext,
    required String authTag,
    String? tempId,
    String messageType = 'text',
  }) {
    send({
      'type': 'chat:send',
      'targetAccountId': targetAccountId,
      'ephemeralPublicKey': ephemeralPublicKey,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'authTag': authTag,
      'tempId': tempId,
      'messageType': messageType,
    });
  }

  void sendChatMessage({
    required String targetAccountId,
    required String content,
    String? tempId,
    String messageType = 'text',
  }) {
    send({
      'type': 'chat:send',
      'targetAccountId': targetAccountId,
      'content': content,
      'tempId': tempId,
      'messageType': messageType,
    });
  }

  void initiateCall({
    required String targetAccountId,
    required String callType, // 'audio' | 'video'
  }) {
    send({
      'type': 'call:initiate',
      'targetAccountId': targetAccountId,
      'callType': callType,
    });
  }

  void acceptCall(String callerAccountId) {
    send({
      'type': 'call:accept',
      'callerAccountId': callerAccountId,
    });
  }

  void rejectCall(String callerAccountId, {String reason = 'declined'}) {
    send({
      'type': 'call:reject',
      'callerAccountId': callerAccountId,
      'reason': reason,
    });
  }

  void cancelCall(String targetAccountId) {
    send({
      'type': 'call:cancel',
      'targetAccountId': targetAccountId,
    });
  }

  void sendReadReceipt(String targetAccountId) {
    send({
      'type': 'chat:read',
      'targetAccountId': targetAccountId,
    });
  }

  void sendWebRtcOffer(String targetAccountId, dynamic sdp) {
    send({
      'type': 'webrtc:offer',
      'targetAccountId': targetAccountId,
      'sdp': sdp,
    });
  }

  void sendWebRtcAnswer(String targetAccountId, dynamic sdp) {
    send({
      'type': 'webrtc:answer',
      'targetAccountId': targetAccountId,
      'sdp': sdp,
    });
  }

  void sendIceCandidate(String targetAccountId, dynamic candidate) {
    send({
      'type': 'webrtc:ice-candidate',
      'targetAccountId': targetAccountId,
      'candidate': candidate,
    });
  }

  void endCall(String targetAccountId) {
    send({
      'type': 'call:hangup',
      'targetAccountId': targetAccountId,
    });
  }

  void disconnect({bool cleanSession = true}) {
    if (cleanSession) {
      _lastWsUrl = null;
      _lastToken = null;
      _reconnectTimer?.cancel();
      _pingTimer?.cancel();
    }
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}
