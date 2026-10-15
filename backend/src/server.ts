import http from 'http';
import path from 'path';
import fs from 'fs';
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { getDb } from './db/database';
import { authRouter } from './routes/auth.routes';
import { usersRouter } from './routes/users.routes';
import { setupWebSocketServer } from './ws/signaling';

dotenv.config();

const app = express();
const PORT = Number(process.env.PORT) || 4000;
const ALT_PORT = 8080;

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'Maan Connect / Tisaal Core Engine',
    timestamp: new Date().toISOString()
  });
});

// API routes
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);

// Resolve APK Path across both local development and cloud hosting
function getApkPath(): string | null {
  const candidatePaths = [
    path.resolve(__dirname, '../public/tisaal.apk'),
    path.resolve(__dirname, '../../mobile/build/web/tisaal.apk'),
    path.resolve(__dirname, '../../mobile/build/app/outputs/flutter-apk/app-debug.apk')
  ];
  for (const p of candidatePaths) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

// APK Download endpoint for Android devices
app.get(['/download/tisaal.apk', '/tisaal.apk'], (_req, res) => {
  const resolvedPath = getApkPath();
  if (resolvedPath) {
    res.download(resolvedPath, 'tisaal.apk');
  } else {
    res.status(404).send('APK is currently compiling. Please refresh in a moment.');
  }
});

// Static Web App serving (built Flutter Web PWA)
function getWebBuildPath(): string | null {
  const candidates = [
    path.resolve(__dirname, '../../mobile/build/web'),
    path.resolve(__dirname, '../public'),
    path.resolve(__dirname, '../../public')
  ];
  for (const p of candidates) {
    if (fs.existsSync(path.join(p, 'index.html'))) return p;
  }
  return null;
}

const webBuildPath = getWebBuildPath();
if (webBuildPath) {
  console.log(`[Tisaal Web] Serving Flutter web app from ${webBuildPath}`);
  app.use(express.static(webBuildPath));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/ws') || req.path === '/health') {
      return next();
    }
    res.sendFile(path.join(webBuildPath, 'index.html'));
  });
}

const server = http.createServer(app);
setupWebSocketServer(server);

// Start server
async function start() {
  try {
    await getDb();
    server.listen(PORT, () => {
      console.log(`[Tisaal Backend] Running on http://localhost:${PORT}`);
      console.log(`[Tisaal Backend] WebSocket Signaling on ws://localhost:${PORT}/ws`);
    });

    // Optional alternate port for local multi-browser testing only
    if (!process.env.RENDER && !process.env.RAILWAY_ENVIRONMENT && PORT != ALT_PORT) {
      try {
        const server8080 = http.createServer(app);
        setupWebSocketServer(server8080);
        server8080.listen(ALT_PORT, () => {
          console.log(`[Tisaal Web] Also listening on http://localhost:${ALT_PORT}`);
        });
      } catch (_) {}
    }
  } catch (err) {
    console.error('Failed to initialize server:', err);
    process.exit(1);
  }
}

start();
