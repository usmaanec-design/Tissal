import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tisaal_mobile/core/crypto/crypto_service.dart';
import 'package:tisaal_mobile/main.dart';
import 'package:tisaal_mobile/providers/auth_provider.dart';
import 'package:tisaal_mobile/providers/call_provider.dart';
import 'package:tisaal_mobile/providers/chat_provider.dart';

void main() {
  group('Cryptographic Identity Tests', () {
    test('generateNewIdentity creates a valid 12-word mnemonic and Ed25519 keypair', () {
      final identity = CryptoService.generateNewIdentity();
      final words = identity.mnemonic.split(' ');

      expect(words.length, equals(12));
      expect(identity.publicKeyHex.length, equals(64)); // 32 bytes hex = 64 chars
      expect(identity.accountId.startsWith('acc_'), isTrue);
      expect(identity.accountId.length, equals(20)); // 'acc_' + 16 chars = 20
    });

    test('deriveIdentityFromMnemonic is 100% deterministic', () {
      const mnemonic = 'apple banana silver canyon tiger ocean galaxy puzzle anchor dynamic flame logic';
      final id1 = CryptoService.deriveIdentityFromMnemonic(mnemonic);
      final id2 = CryptoService.deriveIdentityFromMnemonic(mnemonic);

      expect(id1.publicKeyHex, equals(id2.publicKeyHex));
      expect(id1.accountId, equals(id2.accountId));
      expect(id1.mnemonic, equals(id2.mnemonic));
    });

    test('deriveIdentityFromMnemonicAsync generates X25519 encryption key with domain separation', () async {
      const mnemonic = 'apple banana silver canyon tiger ocean galaxy puzzle anchor dynamic flame logic';
      final id = await CryptoService.deriveIdentityFromMnemonicAsync(mnemonic);

      expect(id.publicEncryptionKeyHex.isNotEmpty, isTrue);
      expect(id.publicEncryptionKeyHex.length, equals(64)); // 32 bytes hex
      expect(id.encryptionSeed32.length, equals(32));

      // Domain separation: Ed25519 signing public key must not equal X25519 DH public key
      expect(id.publicKeyHex, isNot(equals(id.publicEncryptionKeyHex)));
    });

    test('signMessage and verifySignature work correctly', () {
      final identity = CryptoService.generateNewIdentity();
      const message = 'register:testuser:123456';

      final signature = CryptoService.signMessage(identity.privateKey, message);
      expect(signature.isNotEmpty, isTrue);

      final isValid = CryptoService.verifySignature(identity.publicKeyHex, message, signature);
      expect(isValid, isTrue);

      // Negative check: Tampered message fails verification
      final isTamperedValid = CryptoService.verifySignature(identity.publicKeyHex, 'tampered_message', signature);
      expect(isTamperedValid, isFalse);

      // Negative check: Invalid public key fails verification
      final otherIdentity = CryptoService.generateNewIdentity();
      final isWrongKeyValid = CryptoService.verifySignature(otherIdentity.publicKeyHex, message, signature);
      expect(isWrongKeyValid, isFalse);
    });
  });

  group('End-to-End Encryption (E2EE) Security Tests', () {
    const aliceMnemonic = 'apple banana silver canyon tiger ocean galaxy puzzle anchor dynamic flame logic';
    const bobMnemonic = 'venture carbon dynamic forest gravity hidden island journey kingdom liquid mineral nature';
    const charlieMnemonic = 'orbit planet quantum radar secret timber universe vacuum winter yellow zero alert';

    test('Alice encrypts message, Bob successfully decrypts with exact match', () async {
      final alice = await CryptoService.deriveIdentityFromMnemonicAsync(aliceMnemonic);
      final bob = await CryptoService.deriveIdentityFromMnemonicAsync(bobMnemonic);

      const secretMessage = 'Hello Bob! This is an end-to-end encrypted message.';

      // Alice encrypts for Bob using Bob's public encryption key
      final envelope = await CryptoService.encryptPayload(
        recipientPublicEncryptionKeyHex: bob.publicEncryptionKeyHex,
        plaintext: secretMessage,
        senderAccountId: alice.accountId,
        recipientAccountId: bob.accountId,
      );

      expect(envelope.ciphertextHex.isNotEmpty, isTrue);
      expect(envelope.authTagHex.length, equals(32)); // 16 bytes Poly1305 MAC = 32 hex chars
      expect(envelope.nonceHex.length, equals(24)); // 12 bytes nonce = 24 hex chars
      expect(envelope.ephemeralPublicKeyHex.length, equals(64)); // 32 bytes X25519 pubkey = 64 hex chars

      // Bob decrypts payload using Bob's private encryption seed
      final decrypted = await CryptoService.decryptPayload(
        envelope: envelope,
        recipientEncryptionSeed32: bob.encryptionSeed32,
        senderAccountId: alice.accountId,
        recipientAccountId: bob.accountId,
      );

      expect(decrypted, equals(secretMessage));
    });

    test('Tampered ciphertext bit is rejected with authentication failure', () async {
      final alice = await CryptoService.deriveIdentityFromMnemonicAsync(aliceMnemonic);
      final bob = await CryptoService.deriveIdentityFromMnemonicAsync(bobMnemonic);

      final envelope = await CryptoService.encryptPayload(
        recipientPublicEncryptionKeyHex: bob.publicEncryptionKeyHex,
        plaintext: 'Confidential bank transfer authorization',
        senderAccountId: alice.accountId,
        recipientAccountId: bob.accountId,
      );

      // Tamper one character in ciphertext
      final tamperedCiphertext = envelope.ciphertextHex.startsWith('a')
          ? 'b${envelope.ciphertextHex.substring(1)}'
          : 'a${envelope.ciphertextHex.substring(1)}';

      final tamperedEnvelope = EncryptedEnvelope(
        ephemeralPublicKeyHex: envelope.ephemeralPublicKeyHex,
        nonceHex: envelope.nonceHex,
        ciphertextHex: tamperedCiphertext,
        authTagHex: envelope.authTagHex,
      );

      expect(
        () async => await CryptoService.decryptPayload(
          envelope: tamperedEnvelope,
          recipientEncryptionSeed32: bob.encryptionSeed32,
          senderAccountId: alice.accountId,
          recipientAccountId: bob.accountId,
        ),
        throwsA(anything),
      );
    });

    test('Tampered Poly1305 authentication tag is rejected', () async {
      final alice = await CryptoService.deriveIdentityFromMnemonicAsync(aliceMnemonic);
      final bob = await CryptoService.deriveIdentityFromMnemonicAsync(bobMnemonic);

      final envelope = await CryptoService.encryptPayload(
        recipientPublicEncryptionKeyHex: bob.publicEncryptionKeyHex,
        plaintext: 'Nuclear launch codes',
        senderAccountId: alice.accountId,
        recipientAccountId: bob.accountId,
      );

      // Invert last character of auth tag
      final corruptTag = envelope.authTagHex.substring(0, 31) + (envelope.authTagHex.endsWith('0') ? '1' : '0');
      final tamperedEnvelope = EncryptedEnvelope(
        ephemeralPublicKeyHex: envelope.ephemeralPublicKeyHex,
        nonceHex: envelope.nonceHex,
        ciphertextHex: envelope.ciphertextHex,
        authTagHex: corruptTag,
      );

      expect(
        () async => await CryptoService.decryptPayload(
          envelope: tamperedEnvelope,
          recipientEncryptionSeed32: bob.encryptionSeed32,
          senderAccountId: alice.accountId,
          recipientAccountId: bob.accountId,
        ),
        throwsA(anything),
      );
    });

    test('Unauthorized third party (Charlie) cannot decrypt Alice-Bob message', () async {
      final alice = await CryptoService.deriveIdentityFromMnemonicAsync(aliceMnemonic);
      final bob = await CryptoService.deriveIdentityFromMnemonicAsync(bobMnemonic);
      final charlie = await CryptoService.deriveIdentityFromMnemonicAsync(charlieMnemonic);

      final envelope = await CryptoService.encryptPayload(
        recipientPublicEncryptionKeyHex: bob.publicEncryptionKeyHex,
        plaintext: 'Eyes only for Bob',
        senderAccountId: alice.accountId,
        recipientAccountId: bob.accountId,
      );

      // Charlie attempts to decrypt with Charlie's private encryption seed
      expect(
        () async => await CryptoService.decryptPayload(
          envelope: envelope,
          recipientEncryptionSeed32: charlie.encryptionSeed32,
          senderAccountId: alice.accountId,
          recipientAccountId: bob.accountId,
        ),
        throwsA(anything),
      );
    });

    test('Replay and splicing attack rejected via Authenticated Associated Data (AAD)', () async {
      final alice = await CryptoService.deriveIdentityFromMnemonicAsync(aliceMnemonic);
      final bob = await CryptoService.deriveIdentityFromMnemonicAsync(bobMnemonic);

      final envelope = await CryptoService.encryptPayload(
        recipientPublicEncryptionKeyHex: bob.publicEncryptionKeyHex,
        plaintext: 'Transfer \$500 to account',
        senderAccountId: alice.accountId,
        recipientAccountId: bob.accountId,
      );

      // Attacker modifies the sender or recipient account ID bound in AAD
      expect(
        () async => await CryptoService.decryptPayload(
          envelope: envelope,
          recipientEncryptionSeed32: bob.encryptionSeed32,
          senderAccountId: 'acc_attacker_12345678', // Spoofed sender
          recipientAccountId: bob.accountId,
        ),
        throwsA(anything),
      );
    });

    test('Clean recovery: Identical identity and encryption keys derived without server communication', () async {
      const mnemonic = 'apple banana silver canyon tiger ocean galaxy puzzle anchor dynamic flame logic';

      // First installation derivation
      final install1 = await CryptoService.deriveIdentityFromMnemonicAsync(mnemonic);

      // Clean installation on fresh device with no local storage
      final install2 = await CryptoService.deriveIdentityFromMnemonicAsync(mnemonic);

      expect(install1.accountId, equals(install2.accountId));
      expect(install1.publicKeyHex, equals(install2.publicKeyHex));
      expect(install1.publicEncryptionKeyHex, equals(install2.publicEncryptionKeyHex));
      expect(install1.encryptionSeed32, equals(install2.encryptionSeed32));
    });

    test('Identity-key change detection flags unverified key updates (TOFU)', () {
      final chatProvider = ChatProvider();
      const peerId = 'acc_bob_123456789012';
      const initialKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const changedKey = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

      // First interaction pins key (TOFU)
      final firstCheck = chatProvider.verifyOrUpdatePeerEncryptionKey(peerId, initialKey);
      expect(firstCheck, isTrue);
      expect(chatProvider.getPinnedEncryptionKey(peerId), equals(initialKey));

      // Subsequent interaction with same key passes
      final repeatCheck = chatProvider.verifyOrUpdatePeerEncryptionKey(peerId, initialKey);
      expect(repeatCheck, isTrue);

      // Changed key triggers security flag
      final mismatchCheck = chatProvider.verifyOrUpdatePeerEncryptionKey(peerId, changedKey);
      expect(mismatchCheck, isFalse);
    });
  });

  group('Widget Smoke Test', () {
    testWidgets('App renders onboarding or home screen when wrapped with providers', (WidgetTester tester) async {
      final authProvider = AuthProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider(create: (_) => ChatProvider()),
            ChangeNotifierProvider(create: (_) => CallProvider()),
          ],
          child: const TisaalApp(),
        ),
      );

      // The app starts on OnboardingScreen when not authenticated
      expect(find.byType(TisaalApp), findsOneWidget);
    });
  });
}
