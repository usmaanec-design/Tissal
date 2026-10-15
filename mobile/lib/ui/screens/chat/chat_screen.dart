import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/models/models.dart';
import '../../../core/services/api_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/call_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';
import '../call/call_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel peerUser;

  const ChatScreen({super.key, required this.peerUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late UserModel _peerUser;

  @override
  void initState() {
    super.initState();
    _peerUser = widget.peerUser;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chat = context.read<ChatProvider>();
      await chat.loadMessages(_peerUser.accountId);
      await chat.markConversationAsRead(_peerUser.accountId);

      if (_peerUser.publicEncryptionKey.isEmpty) {
        try {
          final updated = await ApiService.getPeerProfile(_peerUser.accountId);
          if (mounted && updated != null) {
            setState(() {
              _peerUser = updated;
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();

    if (auth.currentUser != null) {
      chat.sendMessage(
        myAccountId: auth.currentUser!.accountId,
        peerAccountId: _peerUser.accountId,
        content: text,
        recipientPublicEncryptionKey: _peerUser.publicEncryptionKey,
      );
      _msgController.clear();

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _startCall(String callType) async {
    final callProvider = context.read<CallProvider>();
    await callProvider.startOutgoingCall(
      targetAccountId: _peerUser.accountId,
      targetUsername: _peerUser.username,
      callType: callType,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CallScreen()),
      );
    }
  }

  void _showSafetySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.onlineGreen.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: AppTheme.onlineGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('End-to-End Encryption', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Verified Cryptographic Channel', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recipient Account ID:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    const SizedBox(height: 2),
                    SelectableText(
                      _peerUser.accountId,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text('Public Encryption Key (X25519):', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    const SizedBox(height: 2),
                    SelectableText(
                      _peerUser.publicEncryptionKey.isNotEmpty
                          ? _peerUser.publicEncryptionKey
                          : 'Not yet registered by peer',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Messages sent in this conversation are encrypted on your device and only decipherable by ${_peerUser.displayName}. The server stores only high-entropy ciphertext envelopes.',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: 'Account ID: ${_peerUser.accountId}\nEncryption Key: ${_peerUser.publicEncryptionKey}',
                  ));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Safety credentials copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy Safety Credentials'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final messages = chat.getMessagesForUser(_peerUser.accountId);
    final isOnline = chat.isUserOnline(_peerUser.accountId);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _showSafetySheet,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        _peerUser.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline ? AppTheme.onlineGreen : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.background, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _peerUser.displayName,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_peerUser.publicEncryptionKey.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.lock_rounded, size: 13, color: AppTheme.onlineGreen),
                          ],
                        ],
                      ),
                      Text(
                        '@${_peerUser.username} • ${isOnline ? "Online" : "Offline"}${_peerUser.publicEncryptionKey.isNotEmpty ? " • E2EE" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isOnline ? AppTheme.onlineGreen : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _startCall('audio'),
            icon: const Icon(Icons.call_rounded),
            tooltip: 'Audio Call',
          ),
          IconButton(
            onPressed: () => _startCall('video'),
            icon: const Icon(Icons.videocam_rounded),
            tooltip: 'Video Call',
          ),
          IconButton(
            onPressed: _showSafetySheet,
            icon: const Icon(Icons.shield_outlined, size: 20),
            tooltip: 'Safety Info',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // E2EE Indicator Ribbon
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppTheme.surface.withValues(alpha: 0.6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _peerUser.publicEncryptionKey.isNotEmpty ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 13,
                    color: _peerUser.publicEncryptionKey.isNotEmpty ? AppTheme.onlineGreen : AppTheme.warningAmber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _peerUser.publicEncryptionKey.isNotEmpty
                        ? 'End-to-End Encrypted (X25519 + ChaCha20-Poly1305)'
                        : 'Establishing secure peer key...',
                    style: TextStyle(
                      fontSize: 11,
                      color: _peerUser.publicEncryptionKey.isNotEmpty ? AppTheme.textSecondary : AppTheme.warningAmber,
                    ),
                  ),
                ],
              ),
            ),

            // Messages Area
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.lock_rounded, size: 36, color: AppTheme.primaryLight),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'End-to-End Encrypted Direct Chat',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Type a message below to start chatting.\nMessages are end-to-end encrypted and decrypted on your device only.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, idx) {
                        final msg = messages[idx];

                        // System Security Alert Bubble
                        if (msg.senderAccountId == 'system') {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.warningAmber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.security_rounded, size: 16, color: AppTheme.warningAmber),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      msg.content,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // Decryption Error Bubble
                        final isDecryptionError = msg.content.startsWith('[Decryption Error') ||
                            msg.content.startsWith('[E2EE Message: Authentication');

                        final isMe = msg.senderAccountId == auth.currentUser?.accountId;
                        final timeStr = DateFormat.jm().format(msg.createdAt);

                        if (isDecryptionError) {
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                              decoration: BoxDecoration(
                                color: AppTheme.errorRed.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.gpp_bad_rounded, size: 18, color: AppTheme.errorRed),
                                  const SizedBox(width: 8),
                                  const Flexible(
                                    child: Text(
                                      'Encrypted message (MAC check failed)',
                                      style: TextStyle(fontSize: 13, color: AppTheme.errorRed, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: isMe ? AppTheme.primary : AppTheme.surface,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isMe ? 18 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.content,
                                  style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.3),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white.withValues(alpha: 0.65),
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        msg.isRead
                                            ? Icons.done_all_rounded
                                            : (msg.isDelivered ? Icons.done_all_rounded : Icons.done_rounded),
                                        size: 14,
                                        color: msg.isRead
                                            ? const Color(0xFF38BDF8)
                                            : (msg.isDelivered ? Colors.white70 : Colors.white38),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Message Composer Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.borderDark, width: 0.8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                              decoration: const InputDecoration(
                                hintText: 'Type an encrypted message...',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
