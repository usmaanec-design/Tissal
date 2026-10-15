import { Server as HttpServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { v4 as uuidv4 } from 'uuid';
import { verifyToken } from '../crypto/auth';
import { getDb } from '../db/database';

interface AuthenticatedSocket extends WebSocket {
  accountId?: string;
  username?: string;
  isAlive?: boolean;
}

let globalActiveClients: Map<string, AuthenticatedSocket> | null = null;

export function notifyClient(accountId: string, message: any): boolean {
  if (globalActiveClients) {
    const client = globalActiveClients.get(accountId);
    if (client && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(message));
      return true;
    }
  }
  return false;
}

export function setupWebSocketServer(server: HttpServer) {
  const wss = new WebSocketServer({ server, path: '/ws' });
  const activeClients = new Map<string, AuthenticatedSocket>();
  globalActiveClients = activeClients;

  // Heartbeat interval to check alive connections (every 30 seconds)
  const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
      const socket = ws as AuthenticatedSocket;
      if (socket.isAlive === false) {
        if (socket.accountId) {
          activeClients.delete(socket.accountId);
          broadcastPresence(activeClients, socket.accountId, false);
        }
        return socket.terminate();
      }
      socket.isAlive = false;
      socket.ping();
    });
  }, 30000);

  wss.on('close', () => clearInterval(interval));

  wss.on('connection', (ws: AuthenticatedSocket, req) => {
    ws.isAlive = true;

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    // Extract token from query params or wait for auth message
    try {
      const url = new URL(req.url || '', `http://${req.headers.host}`);
      const token = url.searchParams.get('token');

      if (token) {
        const decoded = verifyToken(token);
        if (decoded) {
          ws.accountId = decoded.accountId;
          ws.username = decoded.username;
          activeClients.set(decoded.accountId, ws);
          broadcastPresence(activeClients, decoded.accountId, true);
          send(ws, { type: 'auth:success', accountId: decoded.accountId, username: decoded.username });
          send(ws, { type: 'presence:init', onlineAccountIds: Array.from(activeClients.keys()) });
        }
      }
    } catch (_) {}

    ws.on('message', async (data) => {
      try {
        const payload = JSON.parse(data.toString());
        await handleSocketMessage(ws, payload, activeClients);
      } catch (err) {
        console.error('Socket error processing message:', err);
      }
    });

    ws.on('close', () => {
      if (ws.accountId) {
        activeClients.delete(ws.accountId);
        broadcastPresence(activeClients, ws.accountId, false);
      }
    });
  });

  return { wss, activeClients };
}

function send(ws: WebSocket, message: any) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function broadcastPresence(activeClients: Map<string, AuthenticatedSocket>, accountId: string, isOnline: boolean) {
  const message = {
    type: 'presence:update',
    accountId,
    isOnline,
    timestamp: new Date().toISOString()
  };

  activeClients.forEach((client) => {
    if (client.accountId !== accountId) {
      send(client, message);
    }
  });
}

async function handleSocketMessage(
  ws: AuthenticatedSocket,
  msg: any,
  activeClients: Map<string, AuthenticatedSocket>
) {
  // If not authenticated yet, check for auth:init message
  if (!ws.accountId) {
    if (msg.type === 'auth:init') {
      const decoded = verifyToken(msg.token);
      if (decoded) {
        ws.accountId = decoded.accountId;
        ws.username = decoded.username;
        activeClients.set(decoded.accountId, ws);
        broadcastPresence(activeClients, decoded.accountId, true);
        send(ws, { type: 'auth:success', accountId: decoded.accountId, username: decoded.username });
        send(ws, { type: 'presence:init', onlineAccountIds: Array.from(activeClients.keys()) });
        return;
      } else {
        send(ws, { type: 'auth:error', message: 'Invalid or expired authentication token' });
        ws.close();
        return;
      }
    } else {
      send(ws, { type: 'auth:required', message: 'Authentication required' });
      return;
    }
  }

  const senderAccountId = ws.accountId;
  const targetAccountId = typeof msg.targetAccountId === 'string' ? msg.targetAccountId.trim() : null;
  const targetClient = targetAccountId ? activeClients.get(targetAccountId) : null;

  switch (msg.type) {
    case 'auth:init': {
      send(ws, { type: 'auth:success', accountId: ws.accountId, username: ws.username });
      send(ws, { type: 'presence:init', onlineAccountIds: Array.from(activeClients.keys()) });
      break;
    }

    // 1. Instant Text Chat Message (E2EE Ciphertext Envelope)
    case 'chat:send': {
      const ciphertext = typeof msg.ciphertext === 'string' ? msg.ciphertext.trim() : (typeof msg.content === 'string' ? msg.content.trim() : '');
      const ephemeralPublicKey = typeof msg.ephemeralPublicKey === 'string' ? msg.ephemeralPublicKey.trim() : '';
      const nonce = typeof msg.nonce === 'string' ? msg.nonce.trim() : '';
      const authTag = typeof msg.authTag === 'string' ? msg.authTag.trim() : '';

      if (!targetAccountId || !ciphertext) return;

      if (ciphertext.length > 20000) {
        send(ws, { type: 'chat:error', message: 'Ciphertext payload exceeds size limits.' });
        return;
      }

      const db = await getDb();

      // Check if blocked by recipient
      const blockCheck = await db.get(
        `SELECT id FROM contacts WHERE sender_account_id = ? AND receiver_account_id = ? AND status = 'blocked'`,
        [targetAccountId, senderAccountId]
      );
      if (blockCheck) {
        send(ws, { type: 'chat:error', message: 'Message could not be delivered.' });
        return;
      }

      const tempId = typeof msg.tempId === 'string' ? msg.tempId.trim() : '';
      const conversationId = [senderAccountId, targetAccountId].sort().join(':');

      // Deduplication: If this exact client tempId was already recorded, don't insert duplicate
      if (tempId) {
        const existing = await db.get(
          `SELECT id, created_at, is_delivered FROM messages WHERE conversation_id = ? AND client_temp_id = ?`,
          [conversationId, tempId]
        );
        if (existing) {
          send(ws, {
            type: 'chat:ack',
            tempId,
            id: existing.id,
            delivered: !!existing.is_delivered,
            createdAt: existing.created_at
          });
          return;
        }
      }

      const messageId = uuidv4();
      const isTargetOnline = !!targetClient;

      await db.run(
        `INSERT INTO messages (id, conversation_id, sender_account_id, receiver_account_id, content, ephemeral_public_key, nonce, ciphertext, auth_tag, message_type, is_delivered, client_temp_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          messageId,
          conversationId,
          senderAccountId,
          targetAccountId,
          '', // Zero-plaintext: server stores empty string for legacy content column
          ephemeralPublicKey,
          nonce,
          ciphertext,
          authTag,
          msg.messageType || 'text',
          isTargetOnline ? 1 : 0,
          tempId
        ]
      );

      const messagePayload = {
        type: 'chat:received',
        id: messageId,
        conversationId,
        senderAccountId,
        receiverAccountId: targetAccountId,
        ephemeralPublicKey,
        nonce,
        ciphertext,
        authTag,
        messageType: msg.messageType || 'text',
        isDelivered: isTargetOnline,
        isRead: false,
        createdAt: new Date().toISOString()
      };

      // Send ack to sender
      send(ws, {
        type: 'chat:ack',
        tempId: tempId,
        id: messageId,
        delivered: isTargetOnline,
        createdAt: messagePayload.createdAt
      });

      // Deliver encrypted envelope to recipient if online
      if (targetClient) {
        send(targetClient, messagePayload);
      }
      break;
    }

    // Read Receipts: Mark conversation messages as read
    case 'chat:read': {
      if (!targetAccountId) return;
      const conversationId = [senderAccountId, targetAccountId].sort().join(':');
      const db = await getDb();
      await db.run(
        `UPDATE messages 
         SET is_read = 1 
         WHERE conversation_id = ? AND sender_account_id = ? AND receiver_account_id = ? AND is_read = 0`,
        [conversationId, targetAccountId, senderAccountId]
      );

      // Notify the original sender so their message ticks turn blue immediately
      if (targetClient) {
        send(targetClient, {
          type: 'chat:read',
          readerAccountId: senderAccountId,
          conversationId,
          timestamp: new Date().toISOString()
        });
      }
      break;
    }

    // 2. WebRTC Call Initiation
    case 'call:initiate': {
      const callType = msg.callType === 'video' ? 'video' : 'audio';
      if (!targetAccountId) return;

      if (!targetClient) {
        send(ws, { type: 'call:failed', targetAccountId, reason: 'user_offline' });
        return;
      }

      const db = await getDb();
      const isBlocked = await db.get(
        `SELECT id FROM contacts WHERE sender_account_id = ? AND receiver_account_id = ? AND status = 'blocked'`,
        [targetAccountId, senderAccountId]
      );
      if (isBlocked) {
        send(ws, { type: 'call:failed', targetAccountId, reason: 'call_declined' });
        return;
      }

      send(targetClient, {
        type: 'call:incoming',
        callerAccountId: senderAccountId,
        callerUsername: ws.username,
        callType
      });
      break;
    }

    // 3. WebRTC Call Accept
    case 'call:accept': {
      const callerAccountId = msg.callerAccountId;
      const caller = activeClients.get(callerAccountId);
      if (caller) {
        send(caller, {
          type: 'call:accepted',
          calleeAccountId: senderAccountId,
          calleeUsername: ws.username
        });
      }
      break;
    }

    // 4. WebRTC Call Reject / Busy
    case 'call:reject': {
      const callerAccountId = msg.callerAccountId;
      const caller = activeClients.get(callerAccountId);
      if (caller) {
        send(caller, {
          type: 'call:rejected',
          calleeAccountId: senderAccountId,
          reason: msg.reason || 'declined'
        });
      }
      break;
    }

    // WebRTC Call Cancel by Caller before answer
    case 'call:cancel': {
      if (targetClient) {
        send(targetClient, {
          type: 'call:cancelled',
          callerAccountId: senderAccountId
        });
      }
      break;
    }

    // 5. WebRTC SDP Offer forwarding
    case 'webrtc:offer': {
      if (targetClient && msg.sdp) {
        send(targetClient, {
          type: 'webrtc:offer',
          senderAccountId,
          sdp: msg.sdp
        });
      }
      break;
    }

    // 6. WebRTC SDP Answer forwarding
    case 'webrtc:answer': {
      if (targetClient && msg.sdp) {
        send(targetClient, {
          type: 'webrtc:answer',
          senderAccountId,
          sdp: msg.sdp
        });
      }
      break;
    }

    // 7. WebRTC ICE Candidate forwarding
    case 'webrtc:ice-candidate': {
      if (targetClient && msg.candidate) {
        send(targetClient, {
          type: 'webrtc:ice-candidate',
          senderAccountId,
          candidate: msg.candidate
        });
      }
      break;
    }

    // 8. Hangup / End Call
    case 'call:hangup': {
      if (targetClient) {
        send(targetClient, {
          type: 'call:ended',
          senderAccountId
        });
      }
      break;
    }

    default:
      console.warn('Unknown message type received on WebSocket:', msg.type);
  }
}
