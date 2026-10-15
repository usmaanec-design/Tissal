import * as ed from '@noble/ed25519';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';

const IS_PROD = process.env.NODE_ENV === 'production';
const JWT_SECRET = process.env.JWT_SECRET || 'tisaal-secure-dev-secret-key-32chars!';

if (IS_PROD && JWT_SECRET === 'tisaal-secure-dev-secret-key-32chars!') {
  throw new Error('FATAL SECURITY ERROR: JWT_SECRET environment variable must be set in production!');
}

export function isValidHex(str: string, expectedLength?: number): boolean {
  if (typeof str !== 'string') return false;
  if (expectedLength && str.length !== expectedLength) return false;
  return /^[0-9a-fA-F]+$/.test(str);
}

export function isValidUsername(username: string): boolean {
  if (typeof username !== 'string') return false;
  // 3-30 chars, alphanumeric with underscore or hyphen
  return /^[a-zA-Z0-9_-]{3,30}$/.test(username);
}

export function generateNonce(): string {
  return crypto.randomBytes(32).toString('hex');
}

export function generateAccountId(publicKeyHex: string): string {
  const hash = crypto.createHash('sha256').update(publicKeyHex.toLowerCase()).digest('hex');
  return `acc_${hash.substring(0, 16)}`;
}

export async function verifySignature(
  signatureHex: string,
  messageHex: string,
  publicKeyHex: string
): Promise<boolean> {
  try {
    const signature = Buffer.from(signatureHex, 'hex');
    const message = Buffer.from(messageHex, 'utf8');
    const publicKey = Buffer.from(publicKeyHex, 'hex');

    return await ed.verifyAsync(signature, message, publicKey);
  } catch (err) {
    console.error('Signature verification error:', err);
    return false;
  }
}

export function createToken(payload: { accountId: string; username: string }): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });
}

export function verifyToken(token: string): { accountId: string; username: string } | null {
  try {
    return jwt.verify(token, JWT_SECRET) as { accountId: string; username: string };
  } catch {
    return null;
  }
}
