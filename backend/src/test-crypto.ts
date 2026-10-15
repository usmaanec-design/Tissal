import * as ed from '@noble/ed25519';
import crypto from 'crypto';

async function testCrypto() {
  console.log('Testing Cryptographic Identity Engine...');

  // Generate private seed (32 bytes)
  const privateKey = ed.utils.randomPrivateKey();
  const publicKey = await ed.getPublicKeyAsync(privateKey);

  const privateKeyHex = Buffer.from(privateKey).toString('hex');
  const publicKeyHex = Buffer.from(publicKey).toString('hex');

  // Generate deterministic Account ID
  const hash = crypto.createHash('sha256').update(publicKeyHex).digest('hex');
  const accountId = `acc_${hash.substring(0, 16)}`;

  console.log('Generated Account ID:', accountId);
  console.log('Public Key (hex):', publicKeyHex);

  // Sign message
  const username = 'usman786';
  const registrationMessage = `register:${username}:${publicKeyHex}`;
  const messageBytes = Buffer.from(registrationMessage, 'utf8');

  const signature = await ed.signAsync(messageBytes, privateKey);
  const signatureHex = Buffer.from(signature).toString('hex');
  console.log('Signature (hex):', signatureHex.substring(0, 32) + '...');

  // Verify
  const isValid = await ed.verifyAsync(signature, messageBytes, publicKey);
  console.log('Verification result:', isValid ? 'SUCCESS (PASS)' : 'FAILURE (FAIL)');

  if (!isValid) {
    throw new Error('Signature verification failed');
  }
}

testCrypto().catch(err => {
  console.error('Test failed:', err);
  process.exit(1);
});
