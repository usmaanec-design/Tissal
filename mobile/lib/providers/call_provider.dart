import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/notification_service.dart';
import '../core/services/ringtone_service.dart';
import '../core/services/webrtc_service.dart';
import '../core/services/websocket_service.dart';
import '../main.dart';
import '../ui/screens/call/call_screen.dart';

enum CallState {
  idle,
  outgoingRinging,
  incomingRinging,
  connected,
  ended,
}

class CallProvider extends ChangeNotifier {
  CallState _state = CallState.idle;
  String? _peerAccountId;
  String? _peerUsername;
  String _callType = 'audio'; // 'audio' | 'video'
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _hasRemoteVideo = false;
  int _callDurationSeconds = 0;
  Timer? _durationTimer;
  StreamSubscription? _callEventSubscription;
  StreamSubscription? _remoteStreamSubscription;

  CallState get state => _state;
  String? get peerAccountId => _peerAccountId;
  String? get peerUsername => _peerUsername;
  String get callType => _callType;
  bool get isMuted => _isMuted;
  bool get isVideoOff => _isVideoOff;
  bool get hasRemoteVideo => _hasRemoteVideo;
  int get callDurationSeconds => _callDurationSeconds;

  void init() {
    _callEventSubscription?.cancel();
    _callEventSubscription = WebSocketService().onCallEvent.listen((event) {
      _handleCallEvent(event);
    });

    WebRtcService().onCallEnded.listen((_) {
      _endCallLocally();
    });

    _remoteStreamSubscription?.cancel();
    _remoteStreamSubscription = WebRtcService().onRemoteStream.listen((stream) {
      final hasVideo = stream != null && stream.getVideoTracks().isNotEmpty;
      if (_hasRemoteVideo != hasVideo) {
        _hasRemoteVideo = hasVideo;
        notifyListeners();
      }
    });
  }

  void _handleCallEvent(Map<String, dynamic> event) async {
    final type = event['type'] as String?;

    switch (type) {
      case 'call:incoming':
        _peerAccountId = event['callerAccountId'];
        _peerUsername = event['callerUsername'];
        _callType = event['callType'] ?? 'audio';
        _state = CallState.incomingRinging;
        _hasRemoteVideo = false;

        // 1. Play loud ringtone on callee device
        RingtoneService.playIncomingRingtone();

        // 2. Present system notification with high-priority call channel
        NotificationService.showCallNotification(
          callerName: _peerUsername ?? 'User',
          callType: _callType,
        );

        notifyListeners();
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const CallScreen()),
        );
        break;

      case 'call:accepted':
        RingtoneService.stop();
        NotificationService.cancelCallNotification();
        _state = CallState.connected;
        _startTimer();
        notifyListeners();

        // Peer accepted! Establish WebRTC media connection and send offer
        if (_peerAccountId != null) {
          try {
            await WebRtcService().startCall(
              targetAccountId: _peerAccountId!,
              isVideo: _callType == 'video',
            );
          } catch (e) {
            debugPrint('[CallProvider] Error initializing media on accepted call: $e');
            _errorMessage = 'Microphone/Camera permission denied or unavailable.';
            _endCallLocally();
          }
        }
        break;

      case 'call:rejected':
      case 'call:failed':
      case 'call:cancelled':
      case 'call:cancel':
        RingtoneService.stop();
        NotificationService.cancelCallNotification();
        _endCallLocally();
        break;

      case 'webrtc:offer':
        final sdp = event['sdp'];
        final callerId = event['senderAccountId'];
        try {
          await WebRtcService().handleIncomingOffer(
            callerAccountId: callerId,
            sdpMap: sdp,
            isVideo: _callType == 'video',
          );
        } catch (e) {
          debugPrint('[CallProvider] Error handling incoming offer: $e');
        }
        break;

      case 'webrtc:answer':
        final sdp = event['sdp'];
        await WebRtcService().handleIncomingAnswer(sdp);
        break;

      case 'webrtc:ice-candidate':
        final candidate = event['candidate'];
        await WebRtcService().handleIncomingIceCandidate(candidate);
        break;

      case 'call:ended':
        _endCallLocally();
        break;
    }
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> startOutgoingCall({
    required String targetAccountId,
    required String targetUsername,
    required String callType,
  }) async {
    _peerAccountId = targetAccountId;
    _peerUsername = targetUsername;
    _callType = callType;
    _errorMessage = null;
    _state = CallState.outgoingRinging;
    _isMuted = false;
    _isVideoOff = false;
    _hasRemoteVideo = false;

    // Caller hears gentle calling pulse, NOT loud incoming ringtone
    RingtoneService.playOutgoingRinging();
    notifyListeners();

    try {
      WebSocketService().initiateCall(
        targetAccountId: targetAccountId,
        callType: callType,
      );
    } catch (e) {
      debugPrint('[CallProvider] Error initiating call: $e');
      _errorMessage = 'Could not initiate call.';
      _endCallLocally();
    }
  }

  Future<void> acceptIncomingCall() async {
    RingtoneService.stop();
    NotificationService.cancelCallNotification();
    if (_peerAccountId != null) {
      WebSocketService().acceptCall(_peerAccountId!);
      _state = CallState.connected;
      _startTimer();
      notifyListeners();
    }
  }

  void rejectIncomingCall() {
    RingtoneService.stop();
    NotificationService.cancelCallNotification();
    if (_peerAccountId != null) {
      WebSocketService().rejectCall(_peerAccountId!);
      _endCallLocally();
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    WebRtcService().toggleMute(_isMuted);
    notifyListeners();
  }

  void toggleVideo() {
    _isVideoOff = !_isVideoOff;
    WebRtcService().toggleVideo(_isVideoOff);
    notifyListeners();
  }

  void switchCamera() {
    WebRtcService().switchCamera();
  }

  Future<void> hangUp() async {
    RingtoneService.stop();
    NotificationService.cancelCallNotification();

    // If caller cancels before callee answered
    if (_state == CallState.outgoingRinging && _peerAccountId != null) {
      WebSocketService().cancelCall(_peerAccountId!);
    }

    await WebRtcService().hangUp();
    _endCallLocally();
  }

  void _endCallLocally() {
    RingtoneService.stop();
    NotificationService.cancelCallNotification();
    _durationTimer?.cancel();
    _durationTimer = null;
    _callDurationSeconds = 0;
    _hasRemoteVideo = false;
    _state = CallState.ended;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 1500), () {
      _state = CallState.idle;
      _peerAccountId = null;
      _peerUsername = null;
      notifyListeners();
    });
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _callDurationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _callEventSubscription?.cancel();
    _remoteStreamSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }
}
