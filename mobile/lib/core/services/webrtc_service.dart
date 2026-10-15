import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'websocket_service.dart';

class WebRtcService {
  static final WebRtcService _instance = WebRtcService._internal();
  factory WebRtcService() => _instance;
  WebRtcService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _isInitialized = false;
  String? _currentTargetAccountId;
  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _queuedIceCandidates = [];

  final StreamController<bool> _callEndedController = StreamController<bool>.broadcast();
  Stream<bool> get onCallEnded => _callEndedController.stream;

  final StreamController<MediaStream?> _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  bool get hasRemoteStream => _remoteStream != null;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> initializeRenderers() async {
    if (!_isInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _isInitialized = true;
    }
  }

  Future<void> startCall({
    required String targetAccountId,
    required bool isVideo,
  }) async {
    _currentTargetAccountId = targetAccountId;
    _hasRemoteDescription = false;
    _queuedIceCandidates.clear();

    await initializeRenderers();
    await _setupPeerConnection(isVideo);

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    WebSocketService().sendWebRtcOffer(
      targetAccountId,
      {'sdp': offer.sdp, 'type': offer.type},
    );
  }

  Future<void> handleIncomingOffer({
    required String callerAccountId,
    required Map<String, dynamic> sdpMap,
    required bool isVideo,
  }) async {
    _currentTargetAccountId = callerAccountId;
    _hasRemoteDescription = false;

    await initializeRenderers();
    await _setupPeerConnection(isVideo);

    final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
    await _peerConnection!.setRemoteDescription(description);
    _hasRemoteDescription = true;
    await _drainQueuedIceCandidates();

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(answer);

    WebSocketService().sendWebRtcAnswer(
      callerAccountId,
      {'sdp': answer.sdp, 'type': answer.type},
    );
  }

  Future<void> handleIncomingAnswer(Map<String, dynamic> sdpMap) async {
    if (_peerConnection != null) {
      final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _peerConnection!.setRemoteDescription(description);
      _hasRemoteDescription = true;
      await _drainQueuedIceCandidates();
    }
  }

  Future<void> handleIncomingIceCandidate(Map<String, dynamic> candidateMap) async {
    final candidate = RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );

    if (_peerConnection != null && _hasRemoteDescription) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        debugPrint('[WebRtcService] Failed to add candidate: $e');
      }
    } else {
      // Buffer early candidates until remote description is set
      _queuedIceCandidates.add(candidate);
    }
  }

  Future<void> _drainQueuedIceCandidates() async {
    if (_peerConnection == null) return;
    while (_queuedIceCandidates.isNotEmpty) {
      final cand = _queuedIceCandidates.removeAt(0);
      try {
        await _peerConnection!.addCandidate(cand);
      } catch (e) {
        debugPrint('[WebRtcService] Drain candidate error: $e');
      }
    }
  }

  Future<void> _setupPeerConnection(bool isVideo) async {
    await _disposePeerConnection();

    _peerConnection = await createPeerConnection(_iceConfig);

    // Get user media (microphone and camera)
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': isVideo
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = _localStream;

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    } catch (e) {
      debugPrint('[WebRtcService] Error getting user media: $e');
    }

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_currentTargetAccountId != null) {
        WebSocketService().sendIceCandidate(
          _currentTargetAccountId!,
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    // Unified-plan track handler
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      debugPrint('[WebRtcService] onTrack kind: ${event.track.kind}, streams: ${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        _remoteStreamController.add(_remoteStream);
      }
    };

    // Plan-B / legacy fallback stream handler
    _peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('[WebRtcService] onAddStream received');
      _remoteStream = stream;
      remoteRenderer.srcObject = _remoteStream;
      _remoteStreamController.add(_remoteStream);
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[WebRtcService] ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        // Handle connection drop
      }
    };
  }

  void toggleMute(bool isMuted) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !isMuted;
      });
    }
  }

  void toggleVideo(bool isVideoDisabled) {
    if (_localStream != null) {
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = !isVideoDisabled;
      });
    }
  }

  Future<void> switchCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
    }
  }

  Future<void> hangUp() async {
    if (_currentTargetAccountId != null) {
      WebSocketService().endCall(_currentTargetAccountId!);
    }
    await _disposePeerConnection();
    _callEndedController.add(true);
  }

  Future<void> _disposePeerConnection() async {
    try {
      _hasRemoteDescription = false;
      _queuedIceCandidates.clear();

      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _localStream = null;

      _remoteStream?.getTracks().forEach((track) => track.stop());
      await _remoteStream?.dispose();
      _remoteStream = null;

      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
      _remoteStreamController.add(null);

      await _peerConnection?.close();
      _peerConnection = null;
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _disposePeerConnection();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
