import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bip39/bip39.dart' as bip39;
import '../../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';

class RestoreAccountScreen extends StatefulWidget {
  const RestoreAccountScreen({super.key});

  @override
  State<RestoreAccountScreen> createState() => _RestoreAccountScreenState();
}

class _RestoreAccountScreenState extends State<RestoreAccountScreen> {
  final TextEditingController _mnemonicController = TextEditingController();

  int get _wordCount {
    final text = _mnemonicController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  @override
  void initState() {
    super.initState();
    _mnemonicController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      setState(() {
        _mnemonicController.text = data!.text!.trim();
      });
    }
  }

  Future<void> _handleRestore() async {
    final input = _mnemonicController.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (!bip39.validateMnemonic(input)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid 12-word recovery phrase. Check word spelling, order, and spaces.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();

    try {
      await authProvider.restoreAccount(input);
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
            content: Text(authProvider.errorMessage ?? 'Failed to restore account. Ensure server is online.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final count = _wordCount;
    final isCountValid = count == 12;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restore Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Security Icon
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.history_edu_rounded, size: 34, color: AppTheme.primaryLight),
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Enter Your 12-Word Recovery Key',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Type or paste your 12 recovery words separated by spaces. Your cryptographic keys will be re-derived deterministically on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Word count status badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recovery Words',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCountValid
                          ? AppTheme.onlineGreen.withValues(alpha: 0.2)
                          : AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCountValid ? AppTheme.onlineGreen : AppTheme.borderDark,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$count / 12 words',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCountValid ? AppTheme.onlineGreen : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _mnemonicController,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'e.g. apple banana silver canyon tiger ocean galaxy puzzle anchor dynamic flame logic',
                  suffixIcon: _mnemonicController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () => _mnemonicController.clear(),
                          icon: const Icon(Icons.clear_rounded, size: 18),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Never share your phrase with anyone.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded, size: 16),
                    label: const Text('Paste Phrase'),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              ElevatedButton(
                onPressed: (authProvider.isLoading || !isCountValid) ? null : _handleRestore,
                child: authProvider.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Restore & Log In'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
