import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db/database';
import {
  generateNonce,
  generateAccountId,
  verifySignature,
  createToken,
  isValidHex,
  isValidUsername
} from '../crypto/auth';

export const authRouter = Router();

// Simple in-memory rate limiter for auth endpoints
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
function checkRateLimit(ip: string, maxRequests = 20, windowMs = 60000): boolean {
  const now = Date.now();
  const record = rateLimitMap.get(ip);
  if (!record || now > record.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + windowMs });
    return true;
  }
  if (record.count >= maxRequests) {
    return false;
  }
  record.count++;
  return true;
}

// Middleware to apply rate limiting
authRouter.use((req: Request, res: Response, next) => {
  const clientIp = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkRateLimit(clientIp, 60, 60000)) {
    res.status(429).json({ error: 'Too many requests. Please slow down.' });
    return;
  }
  next();
});

// Suggest an available auto username (e.g., MC-7K4P92)
authRouter.get('/suggest-username', async (_req: Request, res: Response) => {
  const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  let suggested = '';
  const db = await getDb();

  for (let attempt = 0; attempt < 10; attempt++) {
    let code = '';
    for (let i = 0; i < 6; i++) {
      code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    const candidate = `MC-${code}`;
    const existing = await db.get('SELECT id FROM users WHERE username = ? COLLATE NOCASE', [candidate]);
    if (!existing) {
      suggested = candidate;
      break;
    }
  }

  res.json({ suggestedUsername: suggested });
});

// Check if a specific username is available
authRouter.get('/check-username/:username', async (req: Request, res: Response) => {
  const username = String(req.params.username || '').trim().replace(/^@/, '');
  if (!isValidUsername(username)) {
    res.status(400).json({
      error: 'Invalid username format. Must be 3-30 characters (letters, numbers, underscores, hyphens).'
    });
    return;
  }

  const db = await getDb();
  const existing = await db.get('SELECT id FROM users WHERE username = ? COLLATE NOCASE', [username]);
  res.json({ available: !existing });
});

// Request an auth challenge (nonce) for an accountId or public key
authRouter.post('/challenge', async (req: Request, res: Response) => {
  const { accountId, publicKey } = req.body;
  if (!accountId && !publicKey) {
    res.status(400).json({ error: 'accountId or publicKey is required' });
    return;
  }

  if (publicKey && !isValidHex(publicKey, 64)) {
    res.status(400).json({ error: 'Invalid publicKey format. Must be 64-character hex.' });
    return;
  }

  const targetAccountId = accountId || generateAccountId(publicKey);
  if (!targetAccountId.startsWith('acc_') || targetAccountId.length !== 20) {
    res.status(400).json({ error: 'Invalid accountId format.' });
    return;
  }

  const nonce = generateNonce();
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString(); // 5 minutes validity

  const db = await getDb();
  await db.run(
    `INSERT OR REPLACE INTO auth_nonces (account_id, nonce, expires_at) VALUES (?, ?, ?)`,
    [targetAccountId, nonce, expiresAt]
  );

  res.json({ accountId: targetAccountId, nonce });
});

// Register a new user without phone number or email
authRouter.post('/register', async (req: Request, res: Response) => {
  try {
    const { username, publicKey, publicEncryptionKey, displayName, signature } = req.body;

    if (!username || !publicKey || !signature) {
      res.status(400).json({ error: 'username, publicKey, and signature are required' });
      return;
    }

    const cleanUsername = String(username).trim().replace(/^@/, '');
    if (!isValidUsername(cleanUsername)) {
      res.status(400).json({
        error: 'Invalid username. Must be 3-30 characters (letters, numbers, _, -).'
      });
      return;
    }

    if (!isValidHex(publicKey, 64)) {
      res.status(400).json({ error: 'Invalid publicKey. Must be 64-character hex.' });
      return;
    }

    const cleanEncryptionKey = publicEncryptionKey && isValidHex(publicEncryptionKey, 64)
      ? publicEncryptionKey.toLowerCase()
      : '';

    if (!isValidHex(signature, 128)) {
      res.status(400).json({ error: 'Invalid signature. Must be 128-character hex.' });
      return;
    }

    // Verify cryptographic signature of registration message
    const messageWithEnc = `register:${cleanUsername}:${publicKey}:${cleanEncryptionKey}`;
    const legacyMessage = `register:${cleanUsername}:${publicKey}`;

    let isValid = false;
    if (cleanEncryptionKey) {
      isValid = await verifySignature(signature, messageWithEnc, publicKey);
    }
    if (!isValid) {
      isValid = await verifySignature(signature, legacyMessage, publicKey);
    }

    if (!isValid) {
      res.status(401).json({ error: 'Invalid cryptographic signature for registration' });
      return;
    }

    const accountId = generateAccountId(publicKey);
    const db = await getDb();

    // Check username collision (case-insensitive)
    const existingUsername = await db.get(
      'SELECT id FROM users WHERE username = ? COLLATE NOCASE',
      [cleanUsername]
    );
    if (existingUsername) {
      res.status(409).json({ error: 'Username already taken' });
      return;
    }

    // Check accountId collision
    const existingAccount = await db.get('SELECT id FROM users WHERE account_id = ?', [accountId]);
    if (existingAccount) {
      res.status(409).json({ error: 'Account with this identity key already exists' });
      return;
    }

    const userId = uuidv4();
    const cleanDisplayName = displayName ? String(displayName).trim().substring(0, 50) : cleanUsername;

    await db.run(
      `INSERT INTO users (id, account_id, public_key, public_encryption_key, username, display_name) VALUES (?, ?, ?, ?, ?, ?)`,
      [userId, accountId, publicKey, cleanEncryptionKey, cleanUsername, cleanDisplayName]
    );

    const token = createToken({ accountId, username: cleanUsername });

    res.status(201).json({
      message: 'Account created successfully',
      user: {
        id: userId,
        accountId,
        username: cleanUsername,
        displayName: cleanDisplayName,
        publicKey,
        publicEncryptionKey: cleanEncryptionKey
      },
      token
    });
  } catch (err: any) {
    if (err?.message?.includes('UNIQUE constraint failed')) {
      res.status(409).json({ error: 'Username or Account ID already registered' });
      return;
    }
    console.error('Registration error:', err);
    res.status(500).json({ error: 'Internal server error during registration' });
  }
});

// Login / Recovery by signing the challenge nonce
authRouter.post('/login', async (req: Request, res: Response) => {
  try {
    const { accountId, signature } = req.body;
    if (!accountId || !signature) {
      res.status(400).json({ error: 'accountId and signature are required' });
      return;
    }

    if (!isValidHex(signature, 128)) {
      res.status(400).json({ error: 'Invalid signature format. Must be 128 hex characters.' });
      return;
    }

    const db = await getDb();
    const nonceRecord = await db.get(
      'SELECT nonce, expires_at FROM auth_nonces WHERE account_id = ?',
      [accountId]
    );

    // CRITICAL: Delete nonce IMMEDIATELY (Single-use challenge prevents replay attacks)
    if (nonceRecord) {
      await db.run('DELETE FROM auth_nonces WHERE account_id = ?', [accountId]);
    }

    if (!nonceRecord || Date.now() > new Date(nonceRecord.expires_at).getTime()) {
      res.status(400).json({ error: 'Invalid or expired challenge nonce. Please request a new challenge.' });
      return;
    }

    const user = await db.get('SELECT * FROM users WHERE account_id = ?', [accountId]);
    if (!user) {
      res.status(404).json({ error: 'Account not found. Please register first.' });
      return;
    }

    const isValid = await verifySignature(signature, nonceRecord.nonce, user.public_key);
    if (!isValid) {
      res.status(401).json({ error: 'Invalid cryptographic signature for challenge nonce' });
      return;
    }

    const token = createToken({ accountId: user.account_id, username: user.username });
    res.json({
      message: 'Login successful',
      user: {
        id: user.id,
        accountId: user.account_id,
        username: user.username,
        displayName: user.display_name,
        publicKey: user.public_key,
        publicEncryptionKey: user.public_encryption_key || ''
      },
      token
    });
  } catch (err: any) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error during authentication' });
  }
});
