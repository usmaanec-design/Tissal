import { Router, Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db/database';
import { verifyToken } from '../crypto/auth';
import { notifyClient } from '../ws/signaling';

export const usersRouter = Router();

export interface AuthenticatedRequest extends Request {
  user?: {
    accountId: string;
    username: string;
  };
}

// Authentication middleware
export function requireAuth(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized: Missing or invalid token' });
    return;
  }

  const token = authHeader.split(' ')[1];
  const decoded = verifyToken(token);
  if (!decoded) {
    res.status(401).json({ error: 'Unauthorized: Invalid or expired token' });
    return;
  }

  req.user = decoded;
  next();
}

// Search users by @username or accountId
usersRouter.get('/search', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const query = (req.query.q as string || '').trim().replace(/^@/, '');
  if (!query) {
    res.json({ results: [] });
    return;
  }

  const db = await getDb();
  const currentAccountId = req.user!.accountId;

  const users = await db.all(
    `SELECT account_id, username, display_name, public_key, public_encryption_key, created_at 
     FROM users 
     WHERE (LOWER(username) LIKE LOWER(?) OR account_id = ?) 
       AND account_id != ?
     LIMIT 20`,
    [`%${query}%`, query, currentAccountId]
  );

  res.json({ results: users });
});

// Get current profile
usersRouter.get('/me', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const db = await getDb();
  const user = await db.get(
    `SELECT account_id, username, display_name, public_key, public_encryption_key, created_at FROM users WHERE account_id = ?`,
    [req.user!.accountId]
  );

  if (!user) {
    res.status(404).json({ error: 'User not found' });
    return;
  }

  res.json({ user });
});

// Get public profile / encryption key of another user
usersRouter.get('/profile/:accountId', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const accountId = req.params.accountId;
  const db = await getDb();
  const user = await db.get(
    `SELECT account_id, username, display_name, public_key, public_encryption_key FROM users WHERE account_id = ?`,
    [accountId]
  );

  if (!user) {
    res.status(404).json({ error: 'User not found' });
    return;
  }

  res.json({ user });
});

// Update public encryption key
usersRouter.put('/encryption-key', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const { publicEncryptionKey } = req.body;
  if (!publicEncryptionKey || typeof publicEncryptionKey !== 'string' || publicEncryptionKey.length !== 64) {
    res.status(400).json({ error: 'Valid 64-char hex publicEncryptionKey is required' });
    return;
  }

  const db = await getDb();
  await db.run(
    'UPDATE users SET public_encryption_key = ? WHERE account_id = ?',
    [publicEncryptionKey.toLowerCase(), req.user!.accountId]
  );

  res.json({ message: 'Public encryption key updated successfully' });
});

// Get user contacts
usersRouter.get('/contacts', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const db = await getDb();
  const current = req.user!.accountId;

  const contacts = await db.all(
    `SELECT c.id as contact_id, c.status, c.created_at,
            u.account_id, u.username, u.display_name, u.public_key, u.public_encryption_key,
            (c.sender_account_id = ?) as is_sender
     FROM contacts c
     JOIN users u ON (u.account_id = CASE WHEN c.sender_account_id = ? THEN c.receiver_account_id ELSE c.sender_account_id END)
     WHERE c.sender_account_id = ? OR c.receiver_account_id = ?`,
    [current, current, current, current]
  );

  res.json({ contacts });
});

// Send contact request
usersRouter.post('/contacts/request', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const { targetAccountId } = req.body;
  const current = req.user!.accountId;

  if (!targetAccountId || targetAccountId === current) {
    res.status(400).json({ error: 'Valid targetAccountId is required and cannot be yourself' });
    return;
  }

  const db = await getDb();
  const targetUser = await db.get('SELECT account_id FROM users WHERE account_id = ?', [targetAccountId]);
  if (!targetUser) {
    res.status(404).json({ error: 'Target user not found' });
    return;
  }

  const existing = await db.get(
    `SELECT * FROM contacts 
     WHERE (sender_account_id = ? AND receiver_account_id = ?)
        OR (sender_account_id = ? AND receiver_account_id = ?)`,
    [current, targetAccountId, targetAccountId, current]
  );

  if (existing) {
    res.status(409).json({ error: 'Contact or request already exists', status: existing.status });
    return;
  }

  const id = uuidv4();
  await db.run(
    `INSERT INTO contacts (id, sender_account_id, receiver_account_id, status) VALUES (?, ?, ?, 'pending')`,
    [id, current, targetAccountId]
  );

  notifyClient(targetAccountId, { type: 'contact:updated', action: 'received' });

  res.status(201).json({ message: 'Contact request sent', contactId: id });
});

// Accept or reject contact request
usersRouter.post('/contacts/respond', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const { contactId, action } = req.body; // action: 'accept' | 'reject'
  const current = req.user!.accountId;

  if (!contactId || !['accept', 'reject'].includes(action)) {
    res.status(400).json({ error: 'contactId and valid action (accept/reject) are required' });
    return;
  }

  const db = await getDb();
  const contact = await db.get(
    `SELECT * FROM contacts WHERE id = ? AND receiver_account_id = ? AND status = 'pending'`,
    [contactId, current]
  );

  if (!contact) {
    res.status(404).json({ error: 'Pending request not found' });
    return;
  }

  const newStatus = action === 'accept' ? 'accepted' : 'rejected';
  await db.run(`UPDATE contacts SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`, [newStatus, contactId]);

  notifyClient(contact.sender_account_id, { type: 'contact:updated', action: newStatus });
  notifyClient(contact.receiver_account_id, { type: 'contact:updated', action: newStatus });

  res.json({ message: `Request ${newStatus}`, status: newStatus });
});

// Fetch messages between two users (returns ciphertext envelopes)
usersRouter.get('/messages/:peerAccountId', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const { peerAccountId } = req.params;
  const current = req.user!.accountId;

  const db = await getDb();
  const messages = await db.all(
    `SELECT id, sender_account_id, receiver_account_id, ephemeral_public_key, nonce, ciphertext, auth_tag, message_type, is_delivered, is_read, created_at
     FROM messages
     WHERE (sender_account_id = ? AND receiver_account_id = ?)
        OR (sender_account_id = ? AND receiver_account_id = ?)
     ORDER BY created_at ASC
     LIMIT 100`,
    [current, peerAccountId, peerAccountId, current]
  );

  res.json({ messages });
});

// Send message via HTTP fallback (ensures 100% reliable delivery even if WS momentarily blips)
usersRouter.post('/messages/send', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const { targetAccountId, ephemeralPublicKey, nonce, ciphertext, authTag, tempId, messageType, content } = req.body;
  const senderAccountId = req.user!.accountId;

  if (!targetAccountId) {
    res.status(400).json({ error: 'targetAccountId is required' });
    return;
  }

  const db = await getDb();
  const conversationId = [senderAccountId, targetAccountId].sort().join(':');

  // Deduplication check: if message with this tempId was already recorded, don't re-insert!
  if (tempId) {
    const existing = await db.get(
      `SELECT id, created_at FROM messages WHERE conversation_id = ? AND client_temp_id = ?`,
      [conversationId, tempId]
    );
    if (existing) {
      res.status(200).json({
        success: true,
        messageId: existing.id,
        tempId,
        createdAt: existing.created_at
      });
      return;
    }
  }

  const messageId = uuidv4();

  await db.run(
    `INSERT INTO messages (id, conversation_id, sender_account_id, receiver_account_id, content, ephemeral_public_key, nonce, ciphertext, auth_tag, message_type, is_delivered, client_temp_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)`,
    [
      messageId,
      conversationId,
      senderAccountId,
      targetAccountId,
      content || '',
      ephemeralPublicKey || '',
      nonce || '',
      ciphertext || '',
      authTag || '',
      messageType || 'text',
      tempId || ''
    ]
  );

  // Real-time dispatch to recipient if connected via WebSocket
  notifyClient(targetAccountId, {
    type: 'chat:received',
    id: messageId,
    conversationId,
    senderAccountId,
    receiverAccountId: targetAccountId,
    ephemeralPublicKey,
    nonce,
    ciphertext,
    authTag,
    messageType: messageType || 'text',
    isDelivered: true,
    isRead: false,
    createdAt: new Date().toISOString()
  });

  res.status(201).json({
    success: true,
    messageId,
    tempId,
    createdAt: new Date().toISOString()
  });
});

// Mark messages in conversation as read
usersRouter.post('/messages/read', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  const { peerAccountId } = req.body;
  const current = req.user!.accountId;

  if (!peerAccountId) {
    res.status(400).json({ error: 'peerAccountId is required' });
    return;
  }

  const db = await getDb();
  const conversationId = [current, peerAccountId].sort().join(':');

  await db.run(
    `UPDATE messages 
     SET is_read = 1 
     WHERE conversation_id = ? AND sender_account_id = ? AND receiver_account_id = ? AND is_read = 0`,
    [conversationId, peerAccountId, current]
  );

  notifyClient(peerAccountId, {
    type: 'chat:read',
    readerAccountId: current,
    conversationId,
    timestamp: new Date().toISOString()
  });

  res.json({ success: true });
});
