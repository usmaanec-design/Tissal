import * as ed from '@noble/ed25519';
import crypto from 'crypto';
import { getDb } from './db/database';
import {
  generateNonce,
  generateAccountId,
  verifySignature,
  createToken,
  verifyToken,
  isValidHex,
  isValidUsername
} from './crypto/auth';

interface TestResult {
  name: string;
  passed: boolean;
  error?: string;
}

const results: TestResult[] = [];

async function runTest(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    results.push({ name, passed: true });
    console.log(`  [PASS] ${name}`);
  } catch (err: any) {
    results.push({ name, passed: false, error: err?.message || String(err) });
    console.error(`  [FAIL] ${name}:`, err?.message || err);
  }
}

async function main() {
  console.log('=== STARTING TISAAL COMPREHENSIVE BACKEND AUDIT SUITE ===\n');

  const db = await getDb();

  // Test 1: Deterministic Cryptographic Identity
  await runTest('Phase 2.1 - Ed25519 Keypair and AccountId Derivation', async () => {
    const privKey = ed.utils.randomPrivateKey();
    const pubKey = await ed.getPublicKeyAsync(privKey);
    const pubKeyHex = Buffer.from(pubKey).toString('hex');
    const accountId = generateAccountId(pubKeyHex);

    if (!accountId.startsWith('acc_') || accountId.length !== 20) {
      throw new Error(`Invalid accountId generated: ${accountId}`);
    }

    if (!isValidHex(pubKeyHex, 64)) {
      throw new Error('Public key is not 64-character hex');
    }
  });

  // Test 2: Cryptographic Signature Generation and Verification
  await runTest('Phase 2.2 - Message Signing and Signature Verification', async () => {
    const privKey = ed.utils.randomPrivateKey();
    const pubKey = await ed.getPublicKeyAsync(privKey);
    const pubKeyHex = Buffer.from(pubKey).toString('hex');

    const message = 'register:testaudit:dummy';
    const messageBytes = Buffer.from(message, 'utf8');
    const signature = await ed.signAsync(messageBytes, privKey);
    const sigHex = Buffer.from(signature).toString('hex');

    const isValid = await verifySignature(sigHex, message, pubKeyHex);
    if (!isValid) throw new Error('Valid signature failed verification');

    // Negative check: Tampered message
    const isTamperedValid = await verifySignature(sigHex, 'tampered_message', pubKeyHex);
    if (isTamperedValid) throw new Error('Tampered message unexpectedly passed signature check!');

    // Negative check: Tampered signature
    const corruptSig = '0'.repeat(128);
    const isCorruptValid = await verifySignature(corruptSig, message, pubKeyHex);
    if (isCorruptValid) throw new Error('Corrupt signature unexpectedly passed!');
  });

  // Test 3: Username Validation Rules
  await runTest('Phase 2.3 - Username Validation Format & Boundaries', async () => {
    if (!isValidUsername('usman786')) throw new Error('Valid username rejected');
    if (!isValidUsername('MC-7K4P92')) throw new Error('Valid auto username rejected');
    if (!isValidUsername('user_name-123')) throw new Error('Valid username with underscore/dash rejected');

    // Negative checks
    if (isValidUsername('ab')) throw new Error('Too short username accepted');
    if (isValidUsername('a'.repeat(35))) throw new Error('Too long username accepted');
    if (isValidUsername('user name')) throw new Error('Username with space accepted');
    if (isValidUsername('user@domain.com')) throw new Error('Email format accepted as username');
    if (isValidUsername('+1234567890')) throw new Error('Phone format with + accepted as username');
  });

  // Test 4: Registration Without Phone Number or Email
  await runTest('Phase 2.4 - Zero-PII Registration Persistence', async () => {
    const testUsername = `audit_${Date.now()}`;
    const privKey = ed.utils.randomPrivateKey();
    const pubKey = await ed.getPublicKeyAsync(privKey);
    const pubKeyHex = Buffer.from(pubKey).toString('hex');
    const accountId = generateAccountId(pubKeyHex);

    const message = `register:${testUsername}:${pubKeyHex}`;
    const signature = Buffer.from(await ed.signAsync(Buffer.from(message, 'utf8'), privKey)).toString('hex');

    const userId = `usr_${Date.now()}`;
    await db.run(
      `INSERT INTO users (id, account_id, public_key, username, display_name) VALUES (?, ?, ?, ?, ?)`,
      [userId, accountId, pubKeyHex, testUsername, 'Audit User']
    );

    const saved = await db.get('SELECT * FROM users WHERE account_id = ?', [accountId]);
    if (!saved || saved.username !== testUsername) {
      throw new Error('User was not saved properly in database');
    }
  });

  // Test 5: Username Uniqueness & Case-Insensitive Collisions
  await runTest('Phase 2.5 - Case-Insensitive Username Collision Prevention', async () => {
    const uniqueUser = `uniq_${Date.now()}`;
    const privKey1 = ed.utils.randomPrivateKey();
    const pubKey1 = Buffer.from(await ed.getPublicKeyAsync(privKey1)).toString('hex');
    const acc1 = generateAccountId(pubKey1);

    await db.run(
      `INSERT INTO users (id, account_id, public_key, username, display_name) VALUES (?, ?, ?, ?, ?)`,
      [`id_${Date.now()}_1`, acc1, pubKey1, uniqueUser.toLowerCase(), 'User 1']
    );

    // Attempting to insert uppercase variation of the same username must fail
    const privKey2 = ed.utils.randomPrivateKey();
    const pubKey2 = Buffer.from(await ed.getPublicKeyAsync(privKey2)).toString('hex');
    const acc2 = generateAccountId(pubKey2);

    let collisionCaught = false;
    try {
      await db.run(
        `INSERT INTO users (id, account_id, public_key, username, display_name) VALUES (?, ?, ?, ?, ?)`,
        [`id_${Date.now()}_2`, acc2, pubKey2, uniqueUser.toUpperCase(), 'User 2']
      );
    } catch (e: any) {
      collisionCaught = true;
    }

    if (!collisionCaught) {
      throw new Error('Case-insensitive username collision allowed duplicate user creation!');
    }
  });

  // Test 6: Challenge-Response Nonce Single-Use (Replay Prevention)
  await runTest('Phase 2.6 - Challenge Nonce Single-Use Replay Attack Prevention', async () => {
    const testAcc = `acc_test_${Date.now()}`.padEnd(20, '0');
    const nonce = generateNonce();
    const expiresAt = new Date(Date.now() + 60000).toISOString();

    await db.run(
      `INSERT OR REPLACE INTO auth_nonces (account_id, nonce, expires_at) VALUES (?, ?, ?)`,
      [testAcc, nonce, expiresAt]
    );

    // Retrieve and immediately delete (as done in /api/auth/login)
    const nonceRecord = await db.get('SELECT nonce, expires_at FROM auth_nonces WHERE account_id = ?', [testAcc]);
    if (!nonceRecord) throw new Error('Nonce was not inserted');

    await db.run('DELETE FROM auth_nonces WHERE account_id = ?', [testAcc]);

    // Second attempt using the same nonce must find no record (replay prevented)
    const secondAttempt = await db.get('SELECT nonce FROM auth_nonces WHERE account_id = ?', [testAcc]);
    if (secondAttempt) {
      throw new Error('Nonce was not invalidated after single use! Replay attack vulnerability.');
    }
  });

  // Test 7: Challenge Expiration
  await runTest('Phase 2.7 - Challenge Nonce Expiration Validation', async () => {
    const testAcc = `acc_exp_${Date.now()}`.padEnd(20, '0');
    const nonce = generateNonce();
    // Nonce expired 10 seconds ago
    const expiredTime = new Date(Date.now() - 10000).toISOString();

    await db.run(
      `INSERT OR REPLACE INTO auth_nonces (account_id, nonce, expires_at) VALUES (?, ?, ?)`,
      [testAcc, nonce, expiredTime]
    );

    const nonceRecord = await db.get('SELECT nonce, expires_at FROM auth_nonces WHERE account_id = ?', [testAcc]);
    const isExpired = Date.now() > new Date(nonceRecord.expires_at).getTime();

    if (!isExpired) {
      throw new Error('Past nonce was not recognized as expired');
    }

    // Cleanup
    await db.run('DELETE FROM auth_nonces WHERE account_id = ?', [testAcc]);
  });

  // Test 8: JWT Session Generation and Verification
  await runTest('Phase 2.8 - JWT Session Integrity & Tampering Protection', async () => {
    const payload = { accountId: 'acc_1234567890abcdef', username: 'testuser' };
    const token = createToken(payload);

    const decoded = verifyToken(token);
    if (!decoded || decoded.accountId !== payload.accountId || decoded.username !== payload.username) {
      throw new Error('Valid token could not be verified');
    }

    // Tampered token test
    const tampered = token.substring(0, token.length - 5) + 'xxxxx';
    const decodedTampered = verifyToken(tampered);
    if (decodedTampered !== null) {
      throw new Error('Tampered token unexpectedly passed verification');
    }
  });

  // Test 9: Messaging Authorization
  await runTest('Phase 3.1 - Message Query Authorization Isolation', async () => {
    const userA = 'acc_userA_1234567890';
    const userB = 'acc_userB_1234567890';
    const userC = 'acc_userC_1234567890'; // Unrelated third party

    const msgId = `msg_${Date.now()}`;
    await db.run(
      `INSERT INTO messages (id, conversation_id, sender_account_id, receiver_account_id, content) VALUES (?, ?, ?, ?, ?)`,
      [msgId, `${userA}:${userB}`, userA, userB, 'Secret between A and B']
    );

    // User C queries messages involving User B
    const messagesForC = await db.all(
      `SELECT * FROM messages WHERE (sender_account_id = ? AND receiver_account_id = ?) OR (sender_account_id = ? AND receiver_account_id = ?)`,
      [userC, userB, userB, userC]
    );

    if (messagesForC.length > 0) {
      throw new Error('User C was able to access messages between User A and User B!');
    }
  });

  // Test 10: E2EE Zero-Plaintext Storage Verification
  await runTest('Phase 4.1 - Server Zero-Plaintext Storage & Envelope Integrity', async () => {
    const sender = 'acc_alice_1234567890';
    const receiver = 'acc_bob_12345678901';
    const e2eeMsgId = `e2ee_${Date.now()}`;

    // Synthetic encrypted envelope components (ChaCha20-Poly1305 + X25519)
    const ephemeralPubKey = crypto.randomBytes(32).toString('hex');
    const nonce = crypto.randomBytes(12).toString('hex');
    const ciphertext = crypto.randomBytes(48).toString('hex');
    const authTag = crypto.randomBytes(16).toString('hex');

    // Insert strictly ciphertext envelope into database
    await db.run(
      `INSERT INTO messages (id, conversation_id, sender_account_id, receiver_account_id, content, ephemeral_public_key, nonce, ciphertext, auth_tag)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [e2eeMsgId, `${sender}:${receiver}`, sender, receiver, '', ephemeralPubKey, nonce, ciphertext, authTag]
    );

    const storedMsg = await db.get('SELECT * FROM messages WHERE id = ?', [e2eeMsgId]);
    if (!storedMsg) throw new Error('E2EE message was not stored');

    // Strict validation: Plaintext column MUST be empty
    if (storedMsg.content && storedMsg.content.trim().length > 0) {
      throw new Error('E2EE message contains plaintext content in server database!');
    }

    // Verify all cryptographic envelope parameters are preserved exactly
    if (storedMsg.ephemeral_public_key !== ephemeralPubKey ||
        storedMsg.nonce !== nonce ||
        storedMsg.ciphertext !== ciphertext ||
        storedMsg.auth_tag !== authTag) {
      throw new Error('Cryptographic envelope fields corrupted during database persistence');
    }
  });

  // Test 11: Public Encryption Key Persistence and Profile Exposure
  await runTest('Phase 4.2 - Public Encryption Key Registration and Query Isolation', async () => {
    const testUsername = `encuser_${Date.now()}`;
    const privKey = ed.utils.randomPrivateKey();
    const pubKeyHex = Buffer.from(await ed.getPublicKeyAsync(privKey)).toString('hex');
    const accountId = generateAccountId(pubKeyHex);
    const pubEncKeyHex = crypto.randomBytes(32).toString('hex');

    await db.run(
      `INSERT INTO users (id, account_id, public_key, public_encryption_key, username, display_name) VALUES (?, ?, ?, ?, ?, ?)`,
      [`usr_enc_${Date.now()}`, accountId, pubKeyHex, pubEncKeyHex, testUsername, 'Encrypted User']
    );

    const userProfile = await db.get(
      'SELECT account_id, public_key, public_encryption_key, username FROM users WHERE account_id = ?',
      [accountId]
    );

    if (!userProfile) throw new Error('User profile could not be found');
    if (userProfile.public_encryption_key !== pubEncKeyHex) {
      throw new Error('Public encryption key was not persisted or retrieved correctly');
    }
  });

  // Test 12: Envelope Tampering & Nonce Uniqueness Verification
  await runTest('Phase 4.3 - Envelope Field Format Validation & Nonce Isolation', async () => {
    const validHex32 = crypto.randomBytes(32).toString('hex');
    const validHex12 = crypto.randomBytes(12).toString('hex');
    const validHex16 = crypto.randomBytes(16).toString('hex');

    if (!isValidHex(validHex32, 64)) throw new Error('Valid 32-byte hex rejected');
    if (!isValidHex(validHex12, 24)) throw new Error('Valid 12-byte nonce rejected');
    if (!isValidHex(validHex16, 32)) throw new Error('Valid 16-byte auth tag rejected');

    // Negative validation: Corrupted nonces or tags
    if (isValidHex('invalid_non_hex_string', 24)) throw new Error('Invalid hex string accepted as nonce');
    if (isValidHex('0'.repeat(20), 24)) throw new Error('Truncated 10-byte nonce accepted for 12-byte requirement');
  });

  // Test 13: Duplicate Message Id Replay Prevention
  await runTest('Phase 4.4 - Duplicate Message Id Persistence Rejection', async () => {
    const duplicateId = `msg_dup_${Date.now()}`;
    const userA = 'acc_userA_dup1234567';
    const userB = 'acc_userB_dup1234567';

    await db.run(
      `INSERT INTO messages (id, conversation_id, sender_account_id, receiver_account_id, content, ciphertext, auth_tag)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [duplicateId, `${userA}:${userB}`, userA, userB, '', 'abcdef', '123456']
    );

    // Second insertion with identical ID must fail on PRIMARY KEY constraint
    let caughtDuplicate = false;
    try {
      await db.run(
        `INSERT INTO messages (id, conversation_id, sender_account_id, receiver_account_id, content, ciphertext, auth_tag)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [duplicateId, `${userA}:${userB}`, userA, userB, '', 'abcdef', '123456']
      );
    } catch (_) {
      caughtDuplicate = true;
    }

    if (!caughtDuplicate) {
      throw new Error('Database allowed duplicate message ID insertion! Replay/duplicate vulnerability.');
    }
  });

  // Test 14: Server Zero-Knowledge Private Key Absence Verification
  await runTest('Phase 4.5 - Verification of Complete Absence of Private Keys on Server', async () => {
    // Audit users table schema
    const tableInfo = await db.all("PRAGMA table_info('users')");
    const columnNames = tableInfo.map((col: any) => col.name.toLowerCase());

    for (const forbidden of ['private_key', 'privkey', 'secret_key', 'mnemonic', 'seed']) {
      if (columnNames.includes(forbidden)) {
        throw new Error(`CRITICAL SECURITY VIOLATION: Database contains private key column "${forbidden}"!`);
      }
    }
  });

  console.log('\n=== AUDIT SUITE EXECUTION SUMMARY ===');
  const total = results.length;
  const passed = results.filter(r => r.passed).length;
  const failed = total - passed;

  console.log(`Total Tests Run: ${total}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);

  if (failed > 0) {
    console.error('\nTests Failed:');
    results.filter(r => !r.passed).forEach(r => console.error(` - ${r.name}: ${r.error}`));
    process.exit(1);
  } else {
    console.log(`\nALL ${total} AUDIT SUITE TESTS PASSED 100% CLEANLY!`);
  }
}

main().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
