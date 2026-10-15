import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class RingtoneService {
  static bool _isPlaying = false;
  static Timer? _outgoingToneTimer;

  /// Play loud phone ringtone for incoming call on recipient device
  static void playIncomingRingtone() {
    stop();
    _isPlaying = true;
    try {
      if (!kIsWeb) {
        FlutterRingtonePlayer().playRingtone(
          looping: true,
          volume: 1.0,
          asAlarm: true,
        );
      }
    } catch (e) {
      debugPrint('[RingtoneService] Incoming ringtone error: $e');
    }
  }

  /// Play gentle, subtle calling tone for caller device (standard calling cadence)
  static void playOutgoingRinging() {
    stop();
    _isPlaying = true;
    try {
      if (!kIsWeb) {
        // Immediate first subtle ring pulse
        FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          ios: IosSounds.electronic,
          looping: false,
          volume: 0.25,
        );

        // Repeat subtle ring pulse every 3.5 seconds like standard cellular ringback tone
        _outgoingToneTimer?.cancel();
        _outgoingToneTimer = Timer.periodic(const Duration(milliseconds: 3500), (timer) {
          if (!_isPlaying) {
            timer.cancel();
            return;
          }
          FlutterRingtonePlayer().play(
            android: AndroidSounds.notification,
            ios: IosSounds.electronic,
            looping: false,
            volume: 0.25,
          );
        });
      }
    } catch (e) {
      debugPrint('[RingtoneService] Outgoing ringtone error: $e');
    }
  }

  static void stop() {
    _outgoingToneTimer?.cancel();
    _outgoingToneTimer = null;
    _isPlaying = false;
    try {
      if (!kIsWeb) {
        FlutterRingtonePlayer().stop();
      }
    } catch (e) {
      debugPrint('[RingtoneService] Stop ringtone error: $e');
    }
  }
}
