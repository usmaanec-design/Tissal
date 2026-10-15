import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/server_config_dialog.dart';
import 'create_identity_screen.dart';
import 'restore_account_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // App Brand Logo & Icon
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxKeyShadow(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 58,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // App Title & Tagline
              const Text(
                'Tisaal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Maan Connect • Private Global Communication',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryLight,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Global Communication Without Phone Numbers or SIM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Value Pillars
              _buildPillarItem(
                icon: Icons.phonelink_erase_rounded,
                title: 'No Phone or SIM Required',
                subtitle: 'No SMS verifications, no mobile tracking, zero PII.',
              ),
              const SizedBox(height: 12),
              _buildPillarItem(
                icon: Icons.lock_outline_rounded,
                title: 'End-to-End Encrypted (E2EE)',
                subtitle: 'Direct messaging encrypted with X25519 & ChaCha20-Poly1305.',
              ),
              const SizedBox(height: 12),
              _buildPillarItem(
                icon: Icons.key_rounded,
                title: '12-Word Recovery Key',
                subtitle: 'Deterministic account ownership. You control your private keys.',
              ),
              const SizedBox(height: 12),
              _buildPillarItem(
                icon: Icons.videocam_rounded,
                title: 'Peer-to-Peer Calling',
                subtitle: 'High definition audio and video powered by WebRTC.',
              ),

              const SizedBox(height: 36),

              // Primary Actions
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateIdentityScreen()),
                  );
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Create Identity'),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RestoreAccountScreen()),
                  );
                },
                child: const Text('Restore with Recovery Key'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPillarItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155), width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BoxKeyShadow extends BoxShadow {
  const BoxKeyShadow({
    super.color,
    super.offset,
    super.blurRadius,
  });
}
