import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../theme/app_theme.dart';

class ServerConfigDialog extends StatefulWidget {
  final VoidCallback? onSaved;

  const ServerConfigDialog({super.key, this.onSaved});

  static Future<void> show(BuildContext context, {VoidCallback? onSaved}) {
    return showDialog(
      context: context,
      builder: (_) => ServerConfigDialog(onSaved: onSaved),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late TextEditingController _controller;
  bool _isTesting = false;
  bool? _testSuccess;
  String? _statusText;

  final List<String> _presets = [
    '192.168.25.171:4000',
    '192.168.137.1:4000',
    '192.168.100.17:4000',
    '10.0.2.2:4000',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ApiService.serverHost);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _statusText = 'Pinging server...';
    });

    final success = await ApiService.testConnection(_controller.text.trim());

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _statusText = success
            ? 'Connected successfully to backend!'
            : 'Could not connect. Ensure your mobile and laptop are on the same Wi-Fi / Hotspot.';
      });
    }
  }

  Future<void> _saveAndApply() async {
    final host = _controller.text.trim();
    if (host.isEmpty) return;

    await ApiService.saveServerHost(host);
    if (mounted) {
      widget.onSaved?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server set to: $host'),
          backgroundColor: AppTheme.onlineGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.dns_rounded, color: AppTheme.primaryLight, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Server Connection',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Enter the IP address of your laptop backend server (port 4000):',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Server IP & Port',
                  prefixIcon: const Icon(Icons.lan_rounded, size: 20),
                  suffixIcon: IconButton(
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_rounded),
                    tooltip: 'Test Connection',
                    onPressed: _isTesting ? null : _testConnection,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Presets:',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _presets.map((preset) {
                  return InkWell(
                    onTap: () {
                      _controller.text = preset;
                      _testConnection();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        preset,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.primaryLight),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_statusText != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_testSuccess == true
                            ? AppTheme.onlineGreen
                            : AppTheme.errorRed)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testSuccess == true
                          ? AppTheme.onlineGreen
                          : AppTheme.errorRed,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: _testSuccess == true ? AppTheme.onlineGreen : AppTheme.errorRed,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusText!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testSuccess == true ? AppTheme.onlineGreen : AppTheme.errorRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveAndApply,
                      child: const Text('Save & Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
