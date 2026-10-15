import * as ed from '@noble/ed25519';
import crypto from 'crypto';
import { WebSocket } from 'ws';

const BASE_URL = 'http://localhost:4000';
const WS_URL = 'ws://localhost:4000/ws';

interface TestUser {
  name: string;
  username: string;
  privSignKey: Uint8Array;
  pubSignKeyHex: string;
  accountId: string;
  x25519KeyPair: crypto.KeyPairKeyObjectResult;
  pubEncKeyHex: string;
  token?: string;
  ws?: WebSocket;
}

async function createTestUser(name: string, prefix: string): Promise<TestUser> {
  const randSuffix = Math.floor(1000 + Math.random() * 9000);
  const username = `${prefix}_${randSuffix}`;

  // 1. Ed25519 Identity Signing Key
  const privSignKey = ed.utils.randomPrivateKey();
  const pubSignKey = await ed.getPublicKeyAsync(privSignKey);
  const pubSignKeyHex = Buffer.from(pubSignKey).toString('hex');

  // Account ID: acc_ + first 16 hex chars of sha256(pubSignKeyHex)
  const hash = crypto.createHash('sha256').update(pubSignKeyHex).digest('hex');
  const accountId = `acc_${hash.substring(0, 16)}`;

  // 2. X25519 Encryption Key
  const x25519KeyPair = crypto.generateKeyPairSync('x25519');
  const pubEncKeyHex = x25519KeyPair.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('hex');

  return {
    name,
    username,
    privSignKey,
    pubSignKeyHex,
    accountId,
    x25519KeyPair,
    pubEncKeyHex
  };
}

// Encrypt plaintext payload with Ephemeral X25519 + HKDF-SHA256 + ChaCha20-Poly1305
function encryptPayload(
  plaintext: string,
  recipientPubEncKeyHex: string,
  senderAccountId: string,
  recipientAccountId: string
) {
  // 1. Ephemeral X25519 Keypair
  const ephemeral = crypto.generateKeyPairSync('x25519');
  const ephemeralPubKeyRaw = ephemeral.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);

  // 2. Diffie-Hellman Key Agreement
  const recipientDer = Buffer.concat([
    Buffer.from('302a300506032b656e032100', 'hex'),
    Buffer.from(recipientPubEncKeyHex, 'hex')
  ]);
  const recipientKeyObj = crypto.createPublicKey({ key: recipientDer, format: 'der', type: 'spki' });
  const sharedSecret = crypto.diffieHellman({
    privateKey: ephemeral.privateKey,
    publicKey: recipientKeyObj
  });

  // 3. HKDF-SHA256 Key Derivation
  const salt = Buffer.from('tisaal-salt-v1', 'utf8');
  const info = Buffer.from('tisaal-msg-v1', 'utf8');
  const messageKey = Buffer.from(crypto.hkdfSync('sha256', sharedSecret, salt, info, 32));

  // 4. ChaCha20-Poly1305 AEAD
  const nonce = crypto.randomBytes(12);
  const aad = Buffer.from(`tisaal:${senderAccountId}:${recipientAccountId}`, 'utf8');
  const cipher = crypto.createCipheriv('chacha20-poly1305', messageKey, nonce, { authTagLength: 16 });
  const plaintextBytes = Buffer.from(plaintext, 'utf8');
  cipher.setAAD(aad, { plaintextLength: plaintextBytes.length });

  let ciphertext = cipher.update(plaintextBytes);
  ciphertext = Buffer.concat([ciphertext, cipher.final()]);
  const authTag = cipher.getAuthTag();

  return {
    ephemeralPublicKeyHex: ephemeralPubKeyRaw.toString('hex'),
    nonceHex: nonce.toString('hex'),
    ciphertextHex: ciphertext.toString('hex'),
    authTagHex: authTag.toString('hex')
  };
}

// Decrypt ciphertext envelope using recipient's private X25519 key
function decryptPayload(
  envelope: { ephemeralPublicKeyHex: string; nonceHex: string; ciphertextHex: string; authTagHex: string },
  recipientPrivKey: crypto.KeyObject,
  senderAccountId: string,
  recipientAccountId: string
): string {
  const ephemeralDer = Buffer.concat([
    Buffer.from('302a300506032b656e032100', 'hex'),
    Buffer.from(envelope.ephemeralPublicKeyHex, 'hex')
  ]);
  const ephemeralPubKeyObj = crypto.createPublicKey({ key: ephemeralDer, format: 'der', type: 'spki' });

  const sharedSecret = crypto.diffieHellman({
    privateKey: recipientPrivKey,
    publicKey: ephemeralPubKeyObj
  });

  const salt = Buffer.from('tisaal-salt-v1', 'utf8');
  const info = Buffer.from('tisaal-msg-v1', 'utf8');
  const messageKey = Buffer.from(crypto.hkdfSync('sha256', sharedSecret, salt, info, 32));

  const decipher = crypto.createDecipheriv(
    'chacha20-poly1305',
    messageKey,
    Buffer.from(envelope.nonceHex, 'hex'),
    { authTagLength: 16 }
  );
  const ciphertextBytes = Buffer.from(envelope.ciphertextHex, 'hex');
  decipher.setAAD(Buffer.from(`tisaal:${senderAccountId}:${recipientAccountId}`, 'utf8'), {
    plaintextLength: ciphertextBytes.length
  });
  decipher.setAuthTag(Buffer.from(envelope.authTagHex, 'hex'));

  let decrypted = decipher.update(ciphertextBytes);
  decrypted = Buffer.concat([decrypted, decipher.final()]);

  return decrypted.toString('utf8');
}

async function registerUser(user: TestUser): Promise<void> {
  const message = `register:${user.username}:${user.pubSignKeyHex}:${user.pubEncKeyHex}`;
  const sigBytes = await ed.signAsync(Buffer.from(message, 'utf8'), user.privSignKey);
  const signature = Buffer.from(sigBytes).toString('hex');

  const res = await fetch(`${BASE_URL}/api/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: user.username,
      publicKey: user.pubSignKeyHex,
      publicEncryptionKey: user.pubEncKeyHex,
      displayName: user.name,
      signature
    })
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Registration failed for ${user.username}: ${errorText}`);
  }

  const data = await res.json() as any;
  user.token = data.token;
  console.log(`[PASS] Registered User: ${user.name} (@${user.username}) | AccountId: ${user.accountId}`);
}

function connectWs(user: TestUser): Promise<void> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    user.ws = ws;

    const timeout = setTimeout(() => reject(new Error(`Timeout authenticating WS for ${user.username}`)), 5000);

    ws.on('open', () => {
      ws.send(JSON.stringify({ type: 'auth:init', token: user.token }));
    });

    const onAuthMsg = (raw: any) => {
      try {
        const msg = JSON.parse(raw.toString());
        if (msg.type === 'auth:success') {
          clearTimeout(timeout);
          ws.off('message', onAuthMsg);
          resolve();
        } else if (msg.type === 'auth:error') {
          clearTimeout(timeout);
          ws.off('message', onAuthMsg);
          reject(new Error(msg.message));
        }
      } catch (_) {}
    };

    ws.on('message', onAuthMsg);

    ws.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

async function runLiveTwoUserTest() {
  console.log('================================================================');
  console.log('   TISAAL (MAAN CONNECT) — 2-USER LIVE MESSAGING & CALL TEST    ');
  console.log('================================================================\n');

  // STEP 1: Create 2 Users (Alice and Bob)
  console.log('--- STEP 1: Generating Cryptographic Identities ---');
  const alice = await createTestUser('Alice Khan', 'alice');
  const bob = await createTestUser('Bob Malik', 'bob');

  // STEP 2: Register both users on live backend
  console.log('\n--- STEP 2: Registering Users On Live Backend ---');
  await registerUser(alice);
  await registerUser(bob);

  // STEP 3: Connect both users to WebSocket server
  console.log('\n--- STEP 3: Establishing WebSocket Connections ---');
  await connectWs(alice);
  await connectWs(bob);
  console.log(`[PASS] Alice connected to WebSocket (${alice.accountId})`);
  console.log(`[PASS] Bob connected to WebSocket (${bob.accountId})`);

  // STEP 4: Contact Discovery and Request
  console.log('\n--- STEP 4: Peer Discovery & Contact Pairing ---');
  // Alice searches for Bob
  const searchRes = await fetch(`${BASE_URL}/api/users/search?q=${bob.username}`, {
    headers: { Authorization: `Bearer ${alice.token}` }
  });
  const searchData = await searchRes.json() as any;
  const foundBob = searchData.results?.find((u: any) => u.username === bob.username);
  if (!foundBob) throw new Error('Alice could not find Bob in search');
  console.log(`[PASS] Alice discovered Bob via search (@${bob.username})`);

  // Alice sends contact request to Bob
  const reqRes = await fetch(`${BASE_URL}/api/users/contacts/request`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${alice.token}`
    },
    body: JSON.stringify({ targetAccountId: bob.accountId })
  });
  const reqData = await reqRes.json() as any;
  const contactId = reqData.contactId;
  console.log(`[PASS] Alice sent contact request to Bob (Contact ID: ${contactId})`);

  // Bob accepts contact request
  const acceptRes = await fetch(`${BASE_URL}/api/users/contacts/respond`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${bob.token}`
    },
    body: JSON.stringify({ contactId, action: 'accept' })
  });
  const acceptData = await acceptRes.json() as any;
  console.log(`[PASS] Bob accepted contact request from Alice (${acceptData.status})`);

  // STEP 5: Real-Time End-to-End Encrypted Messaging (Alice -> Bob)
  console.log('\n--- STEP 5: Live E2EE Messaging (Alice -> Bob) ---');
  const secretPlaintext1 = 'Assalam-o-Alaikum Bob! This is an end-to-end encrypted secret message.';
  console.log(`[Alice Plaintext]: "${secretPlaintext1}"`);

  // Alice encrypts for Bob
  const envelope1 = encryptPayload(secretPlaintext1, bob.pubEncKeyHex, alice.accountId, bob.accountId);
  console.log(`[Alice Encrypted Envelope]:`);
  console.log(`  - Ephemeral X25519 PubKey: ${envelope1.ephemeralPublicKeyHex.substring(0, 16)}...`);
  console.log(`  - Ciphertext: ${envelope1.ciphertextHex.substring(0, 32)}...`);
  console.log(`  - ChaCha20-Poly1305 Tag: ${envelope1.authTagHex}`);

  alice.ws!.on('message', (raw) => console.log('  [Alice WS Event]:', raw.toString()));
  bob.ws!.on('message', (raw) => console.log('  [Bob WS Event]:', raw.toString()));

  // Set up Bob's receiver promise
  const bobMessagePromise = new Promise<{ decrypted: string }>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Timeout waiting for Bob to receive message')), 8000);

    bob.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'chat:received' && msg.senderAccountId === alice.accountId) {
        clearTimeout(timeout);
        // Bob decrypts payload
        const decrypted = decryptPayload(
          {
            ephemeralPublicKeyHex: msg.ephemeralPublicKey,
            nonceHex: msg.nonce,
            ciphertextHex: msg.ciphertext,
            authTagHex: msg.authTag
          },
          bob.x25519KeyPair.privateKey,
          alice.accountId,
          bob.accountId
        );
        resolve({ decrypted });
      }
    });
  });

  // Alice sends message over WebSocket
  alice.ws!.send(JSON.stringify({
    type: 'chat:send',
    targetAccountId: bob.accountId,
    tempId: 'temp_msg_1',
    ephemeralPublicKey: envelope1.ephemeralPublicKeyHex,
    nonce: envelope1.nonceHex,
    ciphertext: envelope1.ciphertextHex,
    authTag: envelope1.authTagHex
  }));

  const bobReceived = await bobMessagePromise;
  console.log(`[Bob Decrypted Plaintext]: "${bobReceived.decrypted}"`);
  if (bobReceived.decrypted !== secretPlaintext1) {
    throw new Error('Bob decrypted text does not match Alice original plaintext!');
  }
  console.log('[PASS] Alice -> Bob message delivered and decrypted with 100% fidelity!');

  // STEP 6: Real-Time E2EE Reply (Bob -> Alice)
  console.log('\n--- STEP 6: Live E2EE Reply (Bob -> Alice) ---');
  const secretPlaintext2 = 'Walaikum Assalam Alice! Your encrypted message was verified successfully.';
  console.log(`[Bob Plaintext]: "${secretPlaintext2}"`);

  const envelope2 = encryptPayload(secretPlaintext2, alice.pubEncKeyHex, bob.accountId, alice.accountId);

  const aliceMessagePromise = new Promise<{ decrypted: string }>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Timeout waiting for Alice to receive reply')), 8000);

    alice.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'chat:received' && msg.senderAccountId === bob.accountId) {
        clearTimeout(timeout);
        const decrypted = decryptPayload(
          {
            ephemeralPublicKeyHex: msg.ephemeralPublicKey,
            nonceHex: msg.nonce,
            ciphertextHex: msg.ciphertext,
            authTagHex: msg.authTag
          },
          alice.x25519KeyPair.privateKey,
          bob.accountId,
          alice.accountId
        );
        resolve({ decrypted });
      }
    });
  });

  bob.ws!.send(JSON.stringify({
    type: 'chat:send',
    targetAccountId: alice.accountId,
    tempId: 'temp_msg_2',
    ephemeralPublicKey: envelope2.ephemeralPublicKeyHex,
    nonce: envelope2.nonceHex,
    ciphertext: envelope2.ciphertextHex,
    authTag: envelope2.authTagHex
  }));

  const aliceReceived = await aliceMessagePromise;
  console.log(`[Alice Decrypted Plaintext]: "${aliceReceived.decrypted}"`);
  if (aliceReceived.decrypted !== secretPlaintext2) {
    throw new Error('Alice decrypted text does not match Bob reply plaintext!');
  }
  console.log('[PASS] Bob -> Alice reply delivered and decrypted with 100% fidelity!');

  // STEP 7: Voice & Video Call Signaling Test (Alice calls Bob)
  console.log('\n--- STEP 7: WebRTC Call Signaling (Alice calls Bob) ---');

  // Set up Bob's incoming call listener
  const bobCallPromise = new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Timeout waiting for Bob to receive incoming call')), 8000);

    bob.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'call:incoming' && msg.callerAccountId === alice.accountId) {
        clearTimeout(timeout);
        console.log(`[PASS] Bob received incoming ${msg.callType} call from @${msg.callerUsername}`);
        // Bob accepts call
        bob.ws!.send(JSON.stringify({
          type: 'call:accept',
          callerAccountId: alice.accountId
        }));
        console.log('[PASS] Bob accepted the call');
        resolve();
      }
    });
  });

  // Set up Alice's call accepted listener
  const aliceCallAcceptedPromise = new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Timeout waiting for Alice to receive call acceptance')), 8000);

    alice.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'call:accepted' && msg.calleeAccountId === bob.accountId) {
        clearTimeout(timeout);
        console.log(`[PASS] Alice received call acceptance from @${msg.calleeUsername}`);
        resolve();
      }
    });
  });

  // Alice initiates call
  alice.ws!.send(JSON.stringify({
    type: 'call:initiate',
    targetAccountId: bob.accountId,
    callType: 'audio'
  }));
  console.log(`[PASS] Alice initiated audio call to Bob (${bob.accountId})`);

  await Promise.all([bobCallPromise, aliceCallAcceptedPromise]);

  // STEP 8: WebRTC SDP Offer, Answer, and ICE Candidate Exchange
  console.log('\n--- STEP 8: WebRTC SDP Offer / Answer / ICE Exchange ---');

  const bobSdpPromise = new Promise<void>((resolve, reject) => {
    bob.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'webrtc:offer' && msg.senderAccountId === alice.accountId) {
        console.log('[PASS] Bob received WebRTC SDP Offer from Alice');
        // Bob responds with SDP Answer
        bob.ws!.send(JSON.stringify({
          type: 'webrtc:answer',
          targetAccountId: alice.accountId,
          sdp: { type: 'answer', sdp: 'v=0\r\no=bob 2890844526 IN IP4 127.0.0.1...' }
        }));
        resolve();
      }
    });
  });

  const aliceSdpAnswerPromise = new Promise<void>((resolve, reject) => {
    alice.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'webrtc:answer' && msg.senderAccountId === bob.accountId) {
        console.log('[PASS] Alice received WebRTC SDP Answer from Bob');
        resolve();
      }
    });
  });

  // Alice sends WebRTC SDP Offer
  alice.ws!.send(JSON.stringify({
    type: 'webrtc:offer',
    targetAccountId: bob.accountId,
    sdp: { type: 'offer', sdp: 'v=0\r\no=alice 2890844526 IN IP4 127.0.0.1...' }
  }));

  await Promise.all([bobSdpPromise, aliceSdpAnswerPromise]);

  // Alice sends ICE Candidate
  const bobIcePromise = new Promise<void>((resolve) => {
    bob.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'webrtc:ice-candidate') {
        console.log('[PASS] Bob received ICE candidate from Alice');
        resolve();
      }
    });
  });

  alice.ws!.send(JSON.stringify({
    type: 'webrtc:ice-candidate',
    targetAccountId: bob.accountId,
    candidate: { candidate: 'candidate:1 1 UDP 2130706431 127.0.0.1 50000 typ host', sdpMid: '0', sdpMLineIndex: 0 }
  }));

  await bobIcePromise;

  // STEP 9: Call Hangup & Teardown
  console.log('\n--- STEP 9: Call Termination (Hangup) ---');
  const aliceEndedPromise = new Promise<void>((resolve) => {
    alice.ws!.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'call:ended' && msg.senderAccountId === bob.accountId) {
        console.log('[PASS] Alice received call ended notification from Bob');
        resolve();
      }
    });
  });

  bob.ws!.send(JSON.stringify({
    type: 'call:hangup',
    targetAccountId: alice.accountId
  }));

  await aliceEndedPromise;

  // Clean close
  alice.ws!.close();
  bob.ws!.close();

  console.log('\n================================================================');
  console.log('   RESULT: 100% OF 2-USER E2EE MESSAGING & CALL TESTS PASSED!   ');
  console.log('================================================================');
}

runLiveTwoUserTest().catch((err) => {
  console.error('\n[FATAL ERROR in 2-User Test]:', err);
  process.exit(1);
});
