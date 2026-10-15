import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../providers/call_provider.dart';
import '../../theme/app_theme.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();

    // If call transitioned back to idle, pop the screen
    if (call.state == CallState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }

    final isVideo = call.callType == 'video';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        body: SafeArea(
          child: Stack(
            children: [
              // 1. Background Video Feed (For Connected Video Calls)
              if (call.state == CallState.connected && isVideo) ...[
                if (call.hasRemoteVideo)
                  Positioned.fill(
                    child: RTCVideoView(
                      WebRtcService().remoteRenderer,
                      mirror: false,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          colors: [Color(0xFF1E293B), Color(0xFF090D16)],
                          radius: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 120),
                            const CircularProgressIndicator(color: AppTheme.primaryLight),
                            const SizedBox(height: 16),
                            Text(
                              'Connecting video stream...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Local Pip Camera in Top Right Corner
                Positioned(
                  top: 20,
                  right: 20,
                  width: 110,
                  height: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        border: Border.all(color: Colors.white24, width: 1.5),
                      ),
                      child: RTCVideoView(
                        WebRtcService().localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Audio or Pre-connect Screen
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF090D16)],
                        radius: 1.2,
                      ),
                    ),
                  ),
                ),
              ],

              // 2. Caller / Callee Header Information
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        (call.peerUsername ?? 'U').substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '@${call.peerUsername ?? "User"}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getStatusText(call),
                      style: TextStyle(
                        fontSize: 14,
                        color: call.state == CallState.connected
                            ? AppTheme.onlineGreen
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Call Actions & Controls (Bottom Sheet)
              Positioned(
                bottom: 36,
                left: 0,
                right: 0,
                child: _buildControls(context, call),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusText(CallProvider call) {
    switch (call.state) {
      case CallState.outgoingRinging:
        return 'Calling...';
      case CallState.incomingRinging:
        return 'Incoming ${call.callType} call...';
      case CallState.connected:
        return 'Connected • ${_formatDuration(call.callDurationSeconds)}';
      case CallState.ended:
        return call.errorMessage ?? 'Call Ended';
      case CallState.idle:
        return '';
    }
  }

  Widget _buildControls(BuildContext context, CallProvider call) {
    if (call.state == CallState.incomingRinging) {
      // Incoming Ringing Controls: Green Accept & Red Decline
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Reject Button
          _circleButton(
            icon: Icons.call_end_rounded,
            color: AppTheme.errorRed,
            label: 'Decline',
            onTap: () => call.rejectIncomingCall(),
          ),
          // Accept Button
          _circleButton(
            icon: call.callType == 'video' ? Icons.videocam_rounded : Icons.call_rounded,
            color: AppTheme.callGreen,
            label: 'Accept',
            onTap: () => call.acceptIncomingCall(),
          ),
        ],
      );
    }

    // Active or Outgoing Controls
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute Microphone
        _circleButton(
          icon: call.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: call.isMuted ? Colors.white : AppTheme.surfaceElevated,
          iconColor: call.isMuted ? Colors.black : Colors.white,
          label: call.isMuted ? 'Unmute' : 'Mute',
          onTap: () => call.toggleMute(),
        ),

        // Flip Camera (Only if Video Call)
        if (call.callType == 'video')
          _circleButton(
            icon: Icons.flip_camera_ios_rounded,
            color: AppTheme.surfaceElevated,
            label: 'Flip',
            onTap: () => call.switchCamera(),
          ),

        // End Call Button
        _circleButton(
          icon: Icons.call_end_rounded,
          color: AppTheme.errorRed,
          size: 68,
          label: 'End',
          onTap: () => call.hangUp(),
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    Color iconColor = Colors.white,
    double size = 56,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: size * 0.48),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }
}
