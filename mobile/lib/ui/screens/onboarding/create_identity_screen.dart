import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../core/services/api_service.dart';
import '../../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../../widgets/server_config_dialog.dart';

class CreateIdentityScreen extends StatefulWidget {
  const CreateIdentityScreen({super.key});

  @override
  State<CreateIdentityScreen> createState() => _CreateIdentityScreenState();
}

class _CreateIdentityScreenState extends State<CreateIdentityScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  bool _isAutoId = true;
  String _autoUsername = 'MC-7K4P92';
  bool _isLoadingAuto = false;
  bool _hasSavedSeed = false;
  bool _isPhraseVisible = true;

  late CryptoIdentity _pregeneratedIdentity;

  @override
  void initState() {
    super.initState();
    _pregeneratedIdentity = CryptoService.generateNewIdentity();
    _initAsyncIdentity();
    _fetchAutoUsername();
  }

  void _initAsyncIdentity() async {
    final asyncId = await CryptoService.generateNewIdentityAsync();
    if (mounted) {
      setState(() {
        _pregeneratedIdentity = asyncId;
      });
    }
  }

  Future<void> _fetchAutoUsername() async {
    setState(() => _isLoadingAuto = true);
    final suggested = await ApiService.suggestUsername();
    if (mounted) {
      setState(() {
        _autoUsername = suggested;
        _isLoadingAuto = false;
      });
    }
  }

  void _regenerateSeed() async {
    final newId = await CryptoService.generateNewIdentityAsync();
    if (mounted) {
      setState(() {
        _pregeneratedIdentity = newId;
        _hasSavedSeed = false;
      });
    }
  }

  void _showBackupConfirmDialog(VoidCallback onConfirmed) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: AppTheme.warningAmber, size: 28),
            SizedBox(width: 10),
            Text('Backup Confirmation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Without this 12-word recovery phrase, your account and all conversations CANNOT be recovered if this device is lost, damaged, or cleared.',
              style: TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Tisaal uses zero personal data — there are no SMS resets or email password links.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Review Words'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _hasSavedSeed = true);
              onConfirmed();
            },
            child: const Text('I Have Saved It'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCreate() async {
    final chosenUsername = _isAutoId
        ? _autoUsername
        : _usernameController.text.trim().replaceAll('@', '');

    if (chosenUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide or generate a username')),
      );
      return;
    }

    if (!_hasSavedSeed) {
      _showBackupConfirmDialog(() => _proceedAccountCreation(chosenUsername));
      return;
    }

    await _proceedAccountCreation(chosenUsername);
  }

  Future<void> _proceedAccountCreation(String chosenUsername) async {
    final authProvider = context.read<AuthProvider>();

    try {
      await authProvider.createAccount(
        username: chosenUsername,
        displayName: _displayNameController.text.trim().isNotEmpty
            ? _displayNameController.text.trim()
            : chosenUsername,
        pregeneratedIdentity: _pregeneratedIdentity,
      );

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Failed to connect to server'),
            backgroundColor: AppTheme.errorRed,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Change Server IP',
              textColor: Colors.yellowAccent,
              onPressed: () => ServerConfigDialog.show(context),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final words = _pregeneratedIdentity.mnemonic.split(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Identity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_rounded),
            tooltip: 'Server Connection',
            onPressed: () => ServerConfigDialog.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Identity Type Toggle
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isAutoId = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isAutoId ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Auto-Generate ID',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isAutoId = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isAutoId ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Custom Username',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Username Section
              if (_isAutoId) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.alternate_email_rounded, color: AppTheme.primaryLight),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Generated ID',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            Text(
                              '@$_autoUsername',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isLoadingAuto ? null : _fetchAutoUsername,
                        icon: _isLoadingAuto
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded),
                        tooltip: 'Generate new ID',
                      ),
                    ],
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                    hintText: 'e.g. usman786',
                  ),
                ),
              ],

              const SizedBox(height: 16),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name (Optional)',
                  hintText: 'e.g. Usman Ahmad',
                ),
              ),

              const SizedBox(height: 28),

              // 12-Word Recovery Key Box
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '12-Word Recovery Key',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _isPhraseVisible = !_isPhraseVisible),
                        icon: Icon(
                          _isPhraseVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          size: 20,
                          color: AppTheme.primaryLight,
                        ),
                        tooltip: _isPhraseVisible ? 'Hide words' : 'Show words',
                      ),
                      IconButton(
                        onPressed: _regenerateSeed,
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        tooltip: 'New phrase',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Write this recovery phrase down in a secure place. If you switch or lose your device, this is the only way to recover your account.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 14),

              // 12 Words Grid
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1120),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: words.length,
                      itemBuilder: (context, idx) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155), width: 0.8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _isPhraseVisible ? '${idx + 1}. ${words[idx]}' : '${idx + 1}. ••••••',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _isPhraseVisible ? AppTheme.textPrimary : AppTheme.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _pregeneratedIdentity.mnemonic));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Recovery phrase copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy Recovery Phrase'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Confirmation Checkbox
              CheckboxListTile(
                value: _hasSavedSeed,
                onChanged: (val) => setState(() => _hasSavedSeed = val == true),
                title: const Text(
                  'I have written down and securely stored my recovery key.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppTheme.primary,
              ),

              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton(
                onPressed: authProvider.isLoading ? null : _handleCreate,
                child: authProvider.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Complete & Start Chatting'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
