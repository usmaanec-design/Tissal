import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/models/models.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/call_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';
import '../call/call_screen.dart';
import '../chat/chat_screen.dart';
import '../onboarding/onboarding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _conversationFilterController = TextEditingController();
  String _conversationFilter = '';

  @override
  void initState() {
    super.initState();
    _conversationFilterController.addListener(() {
      setState(() {
        _conversationFilter = _conversationFilterController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        final chat = context.read<ChatProvider>();
        if (auth.identity != null) {
          chat.setMyIdentity(auth.identity!);
        } else {
          chat.setMyAccountId(auth.currentUser!.accountId);
        }
        chat.initSubscriptions();
      }
      context.read<CallProvider>().init();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _conversationFilterController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat.jm().format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat.MMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final isWsConnected = WebSocketService().isConnected;

    // Listen for incoming call and present CallScreen automatically
    if (call.state == CallState.incomingRinging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CallScreen()),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(isWsConnected),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.person_add_rounded),
              onPressed: () => setState(() => _currentIndex = 1),
              tooltip: 'Find Users',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildChatsTab(),
          _buildDiscoveryTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: AppTheme.primaryLight),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search_rounded, color: AppTheme.primaryLight),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield_rounded, color: AppTheme.primaryLight),
            label: 'Security',
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle(bool isConnected) {
    String titleText;
    switch (_currentIndex) {
      case 0:
        titleText = 'Chats';
        break;
      case 1:
        titleText = 'Discover & Contacts';
        break;
      case 2:
        titleText = 'Identity & Security';
        break;
      default:
        titleText = 'Tisaal';
    }

    return Row(
      children: [
        Text(titleText),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isConnected ? AppTheme.onlineGreen : AppTheme.warningAmber,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  // 1. Chats Tab
  Widget _buildChatsTab() {
    final chat = context.watch<ChatProvider>();
    final allAccepted = chat.contacts.where((c) => c.status == 'accepted').toList();

    final filteredContacts = _conversationFilter.isEmpty
        ? allAccepted
        : allAccepted.where((c) {
            return c.username.toLowerCase().contains(_conversationFilter) ||
                c.displayName.toLowerCase().contains(_conversationFilter);
          }).toList();

    if (allAccepted.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.forum_outlined, size: 48, color: AppTheme.primaryLight),
              ),
              const SizedBox(height: 20),
              const Text(
                'No conversations yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect with users by their unique @username or ID to start an end-to-end encrypted direct chat.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => setState(() => _currentIndex = 1),
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: const Text('Find People (@Username)'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Filter bar if multiple conversations
        if (allAccepted.length > 2)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _conversationFilterController,
              decoration: InputDecoration(
                hintText: 'Filter conversations...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                suffixIcon: _conversationFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => _conversationFilterController.clear(),
                      )
                    : null,
              ),
            ),
          ),

        Expanded(
          child: ListView.separated(
            itemCount: filteredContacts.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, color: AppTheme.borderDark),
            itemBuilder: (context, idx) {
              final contact = filteredContacts[idx];
              final isOnline = chat.isUserOnline(contact.accountId);
              final messages = chat.getMessagesForUser(contact.accountId);
              final hasMessages = messages.isNotEmpty;
              final lastMsg = hasMessages ? messages.last.content : 'Direct connection established';
              final timeStr = hasMessages ? _formatTimestamp(messages.last.createdAt) : '';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                leading: Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        contact.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryLight, fontSize: 18),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: isOnline ? AppTheme.onlineGreen : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.background, width: 2.2),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        contact.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    children: [
                      if (contact.publicEncryptionKey.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(right: 4.0),
                          child: Icon(Icons.lock_rounded, size: 12, color: AppTheme.onlineGreen),
                        ),
                      Expanded(
                        child: Text(
                          lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasMessages ? AppTheme.textSecondary : AppTheme.primaryLight,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                onLongPress: () {
                  _confirmDeleteChat(context, chat, contact.accountId, contact.displayName);
                },
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        peerUser: UserModel(
                          accountId: contact.accountId,
                          username: contact.username,
                          displayName: contact.displayName,
                          publicKey: contact.publicKey,
                          publicEncryptionKey: contact.publicEncryptionKey,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 2. Discover & Search Tab
  Widget _buildDiscoveryTab() {
    final chat = context.watch<ChatProvider>();
    final pendingRequests = chat.contacts.where((c) => c.status == 'pending' && !c.isSender).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search Input
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by @username or Account ID...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: AppTheme.primaryLight),
                onPressed: () => chat.searchUsers(_searchController.text),
              ),
            ),
            onSubmitted: (val) => chat.searchUsers(val),
          ),
          const SizedBox(height: 16),

          // Pending Incoming Contact Requests
          if (pendingRequests.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.mark_email_unread_rounded, size: 18, color: AppTheme.warningAmber),
                const SizedBox(width: 8),
                Text(
                  'Incoming Requests (${pendingRequests.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pendingRequests.length,
              itemBuilder: (context, idx) {
                final req = pendingRequests[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        req.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                      ),
                    ),
                    title: Text(req.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('@${req.username}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle_rounded, color: AppTheme.onlineGreen, size: 26),
                          onPressed: () => chat.respondToContact(req.contactId, 'accept'),
                          tooltip: 'Accept',
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_rounded, color: AppTheme.errorRed, size: 26),
                          onPressed: () => chat.respondToContact(req.contactId, 'reject'),
                          tooltip: 'Reject',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],

          // Search Results Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Search Results',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14),
              ),
              if (chat.searchResults.isNotEmpty)
                Text(
                  '${chat.searchResults.length} found',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: chat.isLoading
                ? const Center(child: CircularProgressIndicator())
                : chat.searchResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_rounded, size: 48, color: AppTheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'Type a username above to find users'
                                  : 'No users found matching "${_searchController.text}"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: chat.searchResults.length,
                        itemBuilder: (context, idx) {
                          final user = chat.searchResults[idx];
                          final isAlreadyContact = chat.contacts.any((c) => c.accountId == user.accountId);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(peerUser: user),
                                  ),
                                );
                              },
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                                child: Text(
                                  user.username.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('@${user.username} • ID: ${user.accountId.substring(0, 8)}...'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isAlreadyContact) ...[
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        await chat.sendContactRequest(user.accountId);
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(content: Text('Request sent to @${user.username}')),
                                          );
                                        }
                                      },
                                      child: const Text('Connect', style: TextStyle(fontSize: 11)),
                                    ),
                                    const SizedBox(width: 4),
                                  ] else
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.onlineGreen.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.onlineGreen.withValues(alpha: 0.3)),
                                      ),
                                      child: const Text('Friend', style: TextStyle(color: AppTheme.onlineGreen, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_rounded, color: AppTheme.primaryLight, size: 22),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(peerUser: user),
                                        ),
                                      );
                                    },
                                    tooltip: 'Open Chat',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // 3. Settings & Security Tab
  Widget _buildSettingsTab() {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final identity = auth.identity;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User Identity Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.25),
                  child: Text(
                    (user?.username ?? 'U').substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? 'User',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  '@${user?.username ?? ""}',
                  style: const TextStyle(fontSize: 14, color: AppTheme.primaryLight, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Account ID: ${user?.accountId ?? ""}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          if (user?.accountId != null) {
                            Clipboard.setData(ClipboardData(text: user!.accountId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Account ID copied to clipboard!')),
                            );
                          }
                        },
                        child: const Icon(Icons.copy_rounded, size: 14, color: AppTheme.primaryLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Security & Cryptography Card
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.vpn_key_rounded, color: AppTheme.primaryLight),
                  title: const Text('View 12-Word Recovery Key'),
                  subtitle: const Text('Back up your account key phrase safely'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    if (identity != null) {
                      _showRecoveryKeyDialog(identity.mnemonic);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Identity key is securely isolated in session storage.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: AppTheme.borderDark),
                ListTile(
                  leading: const Icon(Icons.lock_rounded, color: AppTheme.onlineGreen),
                  title: const Text('End-to-End Encryption'),
                  subtitle: const Text('RFC 7748 X25519 + ChaCha20-Poly1305 AEAD'),
                  trailing: const Icon(Icons.info_outline_rounded, size: 18),
                  onTap: _showE2EEInfoDialog,
                ),
                const Divider(height: 1, color: AppTheme.borderDark),
                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: AppTheme.primaryLight),
                  title: const Text('Server Connection Host'),
                  subtitle: Text(ApiService.baseUrl),
                  trailing: const Icon(Icons.edit_rounded, size: 18),
                  onTap: _showServerConfigDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Privacy Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.onlineGreen.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppTheme.onlineGreen, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zero-PII Architecture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 2),
                        Text(
                          'No phone number, email, or IMEI is ever requested or saved on any server.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Logout Button
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(auth),
            icon: const Icon(Icons.logout_rounded, color: AppTheme.errorRed),
            label: const Text('Log Out', style: TextStyle(color: AppTheme.errorRed)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.errorRed, width: 1),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _confirmDeleteChat(BuildContext context, ChatProvider chat, String peerAccountId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete chat with $name?'),
        content: const Text(
          'This will permanently delete this conversation and its messages from your device.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await chat.deleteConversation(peerAccountId);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Chat with $name deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Log Out of Tisaal?'),
        content: const Text(
          'Make sure you have backed up your 12-word recovery phrase. Logging out clears local session storage.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () async {
              Navigator.pop(ctx);
              await auth.logout();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showRecoveryKeyDialog(String mnemonic) {
    final words = mnemonic.split(' ');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.key_rounded, color: AppTheme.primaryLight),
            SizedBox(width: 8),
            Text('12-Word Recovery Key', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anyone with these words can restore your account. Never share them with anyone.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(words.length, (idx) {
                  return Chip(
                    label: Text('${idx + 1}. ${words[idx]}', style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.surfaceElevated,
                    padding: const EdgeInsets.all(4),
                  );
                }),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: mnemonic));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recovery phrase copied!')),
              );
            },
            child: const Text('Copy Phrase'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showE2EEInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: AppTheme.onlineGreen, size: 24),
            SizedBox(width: 8),
            Text('End-to-End Encryption', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All 1-to-1 direct messaging is cryptographically encrypted on your device and can only be decrypted on the recipient’s authorized device.',
              style: TextStyle(fontSize: 13.5, height: 1.4),
            ),
            SizedBox(height: 12),
            Text('• Key Exchange: RFC 7748 X25519 ECDH', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            Text('• Key Derivation: RFC 5869 HKDF-SHA256', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            Text('• Authenticated Cipher: RFC 8439 ChaCha20-Poly1305 AEAD', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            Text('• Server Persistence: Strictly Ciphertext Envelopes', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  void _showServerConfigDialog() {
    final currentHost = ApiService.baseUrl.replaceAll('http://', '').replaceAll('/api', '');
    final controller = TextEditingController(text: currentHost);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Configure Backend Host'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Host:Port',
                hintText: 'e.g. localhost:4000 or 10.0.2.2:4000',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ActionChip(
                  label: const Text('localhost:4000'),
                  onPressed: () => controller.text = 'localhost:4000',
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('10.0.2.2:4000'),
                  onPressed: () => controller.text = '10.0.2.2:4000',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ApiService.setServerHost(controller.text.trim());
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Backend host set to: ${ApiService.baseUrl}')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
