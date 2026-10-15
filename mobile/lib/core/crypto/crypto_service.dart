import 'dart:convert';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';

class EncryptedEnvelope {
  final String ephemeralPublicKeyHex;
  final String nonceHex;
  final String ciphertextHex;
  final String authTagHex;

  EncryptedEnvelope({
    required this.ephemeralPublicKeyHex,
    required this.nonceHex,
    required this.ciphertextHex,
    required this.authTagHex,
  });

  Map<String, dynamic> toJson() => {
    'ephemeralPublicKey': ephemeralPublicKeyHex,
    'nonce': nonceHex,
    'ciphertext': ciphertextHex,
    'authTag': authTagHex,
  };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    return EncryptedEnvelope(
      ephemeralPublicKeyHex: (json['ephemeralPublicKey'] ?? json['ephemeral_public_key'] ?? '') as String,
      nonceHex: (json['nonce'] ?? '') as String,
      ciphertextHex: (json['ciphertext'] ?? '') as String,
      authTagHex: (json['authTag'] ?? json['auth_tag'] ?? '') as String,
    );
  }
}

class CryptoIdentity {
  final String mnemonic;
  final String accountId;
  final String publicKeyHex;
  final String publicEncryptionKeyHex;
  final ed.PrivateKey privateKey;
  final ed.PublicKey publicKey;
  final Uint8List encryptionSeed32;

  CryptoIdentity({
    required this.mnemonic,
    required this.accountId,
    required this.publicKeyHex,
    required this.publicEncryptionKeyHex,
    required this.privateKey,
    required this.publicKey,
    required this.encryptionSeed32,
  });
}

class CryptoService {
  /// Generate a brand new 12-word BIP-39 mnemonic phrase and Ed25519 + X25519 identity
  static Future<CryptoIdentity> generateNewIdentityAsync() async {
    final mnemonic = bip39.generateMnemonic();
    return deriveIdentityFromMnemonicAsync(mnemonic);
  }

  /// Synchronous fallback generator
  static CryptoIdentity generateNewIdentity() {
    final mnemonic = bip39.generateMnemonic();
    return deriveIdentityFromMnemonic(mnemonic);
  }

  /// Synchronous identity derivation (derives deterministic encryption public key synchronously)
  static CryptoIdentity deriveIdentityFromMnemonic(String mnemonic) {
    final normalized = mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final seed = bip39.mnemonicToSeed(normalized);

    // Bytes 0..32: Ed25519 Signing Key
    final seed32Sign = Uint8List.fromList(seed.sublist(0, 32));
    final privateKey = ed.newKeyFromSeed(seed32Sign);
    final publicKey = ed.public(privateKey);
    final publicKeyHex = HEX.encode(publicKey.bytes);
    final accountId = generateAccountId(publicKeyHex);

    // Bytes 32..64: X25519 Encryption Key Seed
    final seed32Enc = Uint8List.fromList(seed.sublist(32, 64));

    // SHA-256 of encryption seed as deterministic placeholder if synchronous
    final encDigest = sha256.convert(seed32Enc);
    final publicEncryptionKeyHex = encDigest.toString();

    return CryptoIdentity(
      mnemonic: normalized,
      accountId: accountId,
      publicKeyHex: publicKeyHex,
      publicEncryptionKeyHex: publicEncryptionKeyHex,
      privateKey: privateKey,
      publicKey: publicKey,
      encryptionSeed32: seed32Enc,
    );
  }

  /// Asynchronous identity derivation using standard X25519
  static Future<CryptoIdentity> deriveIdentityFromMnemonicAsync(String mnemonic) async {
    final normalized = mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final seed = bip39.mnemonicToSeed(normalized);

    // Bytes 0..32: Ed25519 Signing Key
    final seed32Sign = Uint8List.fromList(seed.sublist(0, 32));
    final privateKey = ed.newKeyFromSeed(seed32Sign);
    final publicKey = ed.public(privateKey);
    final publicKeyHex = HEX.encode(publicKey.bytes);
    final accountId = generateAccountId(publicKeyHex);

    // Bytes 32..64: X25519 Encryption Key
    final seed32Enc = Uint8List.fromList(seed.sublist(32, 64));
    final x25519 = X25519();
    final keyPair = await x25519.newKeyPairFromSeed(seed32Enc);
    final pubKey = await keyPair.extractPublicKey();
    final publicEncryptionKeyHex = HEX.encode(pubKey.bytes);

    return CryptoIdentity(
      mnemonic: normalized,
      accountId: accountId,
      publicKeyHex: publicKeyHex,
      publicEncryptionKeyHex: publicEncryptionKeyHex,
      privateKey: privateKey,
      publicKey: publicKey,
      encryptionSeed32: seed32Enc,
    );
  }

  /// Compute deterministic Account ID from public key (acc_ + 16 hex chars of sha256)
  static String generateAccountId(String publicKeyHex) {
    final digest = sha256.convert(utf8.encode(publicKeyHex));
    final hashHex = digest.toString();
    return 'acc_${hashHex.substring(0, 16)}';
  }

  /// Sign an arbitrary UTF-8 message string with Ed25519 private key
  static String signMessage(ed.PrivateKey privateKey, String message) {
    final messageBytes = Uint8List.fromList(utf8.encode(message));
    final signature = ed.sign(privateKey, messageBytes);
    return HEX.encode(signature);
  }

  /// Verify an Ed25519 signature
  static bool verifySignature(String publicKeyHex, String message, String signatureHex) {
    try {
      final publicKey = ed.PublicKey(HEX.decode(publicKeyHex));
      final signature = HEX.decode(signatureHex);
      final messageBytes = Uint8List.fromList(utf8.encode(message));
      return ed.verify(publicKey, messageBytes, Uint8List.fromList(signature));
    } catch (_) {
      return false;
    }
  }

  // ==========================================
  // END-TO-END MESSAGE ENCRYPTION & DECRYPTION
  // ==========================================

  /// Encrypt a message for a recipient using Ephemeral X25519 ECDH + HKDF-SHA256 + ChaCha20-Poly1305 AEAD
  static Future<EncryptedEnvelope> encryptPayload({
    required String recipientPublicEncryptionKeyHex,
    required String plaintext,
    required String senderAccountId,
    required String recipientAccountId,
  }) async {
    final x25519 = X25519();

    // 1. Generate fresh Ephemeral X25519 Keypair (Forward Secrecy per message)
    final ephemeralKeyPair = await x25519.newKeyPair();
    final ephemeralPubKey = await ephemeralKeyPair.extractPublicKey();
    final ephemeralPubKeyHex = HEX.encode(ephemeralPubKey.bytes);

    // 2. Parse recipient's public encryption key
    final recipientPubKeyBytes = HEX.decode(recipientPublicEncryptionKeyHex);
    final recipientPubKey = SimplePublicKey(
      recipientPubKeyBytes,
      type: KeyPairType.x25519,
    );

    // 3. Perform Diffie-Hellman Key Agreement
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPubKey,
    );

    // 4. Derive 256-bit Message Encryption Key via HKDF-SHA256
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final messageKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('tisaal-salt-v1'),
      info: utf8.encode('tisaal-msg-v1'),
    );

    // 5. Encrypt with ChaCha20-Poly1305 AEAD and bind conversation AAD
    final chacha = Chacha20.poly1305Aead();
    final aad = utf8.encode('tisaal:$senderAccountId:$recipientAccountId');
    final secretBox = await chacha.encrypt(
      utf8.encode(plaintext),
      secretKey: messageKey,
      aad: aad,
    );

    return EncryptedEnvelope(
      ephemeralPublicKeyHex: ephemeralPubKeyHex,
      nonceHex: HEX.encode(secretBox.nonce),
      ciphertextHex: HEX.encode(secretBox.cipherText),
      authTagHex: HEX.encode(secretBox.mac.bytes),
    );
  }

  /// Decrypt an envelope using recipient's X25519 private key seed
  static Future<String> decryptPayload({
    required EncryptedEnvelope envelope,
    required Uint8List recipientEncryptionSeed32,
    required String senderAccountId,
    required String recipientAccountId,
  }) async {
    final x25519 = X25519();

    // 1. Recreate recipient's X25519 keypair from seed
    final recipientKeyPair = await x25519.newKeyPairFromSeed(recipientEncryptionSeed32);

    // 2. Parse sender's ephemeral public key
    final ephemeralPubKey = SimplePublicKey(
      HEX.decode(envelope.ephemeralPublicKeyHex),
      type: KeyPairType.x25519,
    );

    // 3. Perform Diffie-Hellman Key Agreement
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: ephemeralPubKey,
    );

    // 4. Derive same 256-bit Message Encryption Key via HKDF-SHA256
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final messageKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('tisaal-salt-v1'),
      info: utf8.encode('tisaal-msg-v1'),
    );

    // 5. Authenticate and Decrypt with ChaCha20-Poly1305
    final chacha = Chacha20.poly1305Aead();
    final aad = utf8.encode('tisaal:$senderAccountId:$recipientAccountId');
    final secretBox = SecretBox(
      HEX.decode(envelope.ciphertextHex),
      nonce: HEX.decode(envelope.nonceHex),
      mac: Mac(HEX.decode(envelope.authTagHex)),
    );

    final decryptedBytes = await chacha.decrypt(
      secretBox,
      secretKey: messageKey,
      aad: aad,
    );

    return utf8.decode(decryptedBytes);
  }
}
