'use strict';

const http = require('http');
const os   = require('os');

// ── Configuration ─────────────────────────────────────────────────────────────
const PORT       = parseInt(process.env.PORT          || '3000', 10);
const VERSION    = process.env.APP_VERSION             || 'v2.0.0';
const BUILD      = process.env.BUILD_ID                || 'canary-001';
const ENV        = process.env.APP_ENV                 || 'production';
const TRACK      = process.env.TRACK                   || 'canary';
// Inject fault rate via env for chaos testing (default 3% in canary)
const FAULT_RATE = parseFloat(process.env.FAULT_RATE   || '0.03');

// ── Telemetry ─────────────────────────────────────────────────────────────────
const startTime = Date.now();
let reqTotal    = 0;
let reqErrors   = 0;
let reqDurMs    = 0;

const now    = () => new Date().toISOString();
const upSec  = () => Math.floor((Date.now() - startTime) / 1000);

function log(level, msg, meta = {}) {
  process.stdout.write(JSON.stringify({
    ts: now(), level, version: VERSION, build: BUILD,
    host: os.hostname(), env: ENV, track: TRACK, msg, ...meta
  }) + '\n');
}

// ── HTTP server ───────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  const t0 = Date.now();
  reqTotal++;

  const done = (code) => {
    const dur = Date.now() - t0;
    reqDurMs += dur;
    if (code >= 500) reqErrors++;
    res.setHeader('x-app-version', VERSION);
    res.setHeader('x-track',       TRACK);
    res.setHeader('x-build-id',    BUILD);
    res.setHeader('x-request-id',  `${Date.now()}-${Math.random().toString(36).slice(2,8)}`);
    log('info', `${req.method} ${req.url} ${code}`, { ms: dur, fault_rate: FAULT_RATE });
  };

  // ── Probes ─────────────────────────────────────────────────────────────────
  if (req.url === '/healthz') {
    done(200);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok', version: VERSION, uptime: upSec() }));
  }
  if (req.url === '/readyz') {
    done(200);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ready: true, version: VERSION }));
  }

  // ── Prometheus metrics ─────────────────────────────────────────────────────
  if (req.url === '/metrics') {
    const avgMs   = reqTotal ? (reqDurMs / reqTotal).toFixed(2) : 0;
    const errRate = reqTotal ? ((reqErrors / reqTotal) * 100).toFixed(4) : 0;
    const body = [
      '# HELP app_http_requests_total Total HTTP requests received',
      '# TYPE app_http_requests_total counter',
      `app_http_requests_total{version="${VERSION}",track="${TRACK}",env="${ENV}"} ${reqTotal}`,
      '',
      '# HELP app_http_errors_total Total HTTP 5xx errors',
      '# TYPE app_http_errors_total counter',
      `app_http_errors_total{version="${VERSION}",track="${TRACK}",env="${ENV}"} ${reqErrors}`,
      '',
      '# HELP app_error_rate_pct Rolling error rate percentage',
      '# TYPE app_error_rate_pct gauge',
      `app_error_rate_pct{version="${VERSION}",track="${TRACK}",env="${ENV}"} ${errRate}`,
      '',
      '# HELP app_latency_avg_ms Average request latency in milliseconds',
      '# TYPE app_latency_avg_ms gauge',
      `app_latency_avg_ms{version="${VERSION}",track="${TRACK}",env="${ENV}"} ${avgMs}`,
      '',
      '# HELP app_uptime_seconds Process uptime in seconds',
      '# TYPE app_uptime_seconds gauge',
      `app_uptime_seconds{version="${VERSION}",track="${TRACK}",env="${ENV}"} ${upSec()}`,
      '',
      '# HELP app_fault_rate_configured Configured fault injection rate',
      '# TYPE app_fault_rate_configured gauge',
      `app_fault_rate_configured{version="${VERSION}",track="${TRACK}"} ${FAULT_RATE}`,
    ].join('\n') + '\n';
    done(200);
    res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8' });
    return res.end(body);
  }

  // ── App info ───────────────────────────────────────────────────────────────
  if (req.url === '/info') {
    done(200);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({
      version: VERSION, build: BUILD, track: TRACK, env: ENV,
      hostname: os.hostname(), platform: os.platform(),
      nodeVersion: process.version, uptime: upSec(),
      memory: process.memoryUsage(), faultRate: FAULT_RATE,
      features: ['dark-theme', 'api-v2', 'websocket-support', 'redis-cache'],
      stats: { requests: reqTotal, errors: reqErrors,
               avgLatencyMs: reqTotal ? +(reqDurMs/reqTotal).toFixed(2) : 0 }
    }, null, 2));
  }

  // ── Chaos: inject configured fault rate ───────────────────────────────────
  if (Math.random() < FAULT_RATE) {
    done(500);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    log('error', 'Fault injected', { fault_rate: FAULT_RATE });
    return res.end(JSON.stringify({ error: 'Internal Server Error', injected: true, version: VERSION }));
  }

  // ── Simulate added latency for new feature (p99 regression test) ──────────
  const extraLatency = Math.random() < 0.1 ? Math.floor(Math.random() * 80) : 0;

  setTimeout(() => {
    const errRate = reqTotal ? ((reqErrors / reqTotal)*100).toFixed(1) : '0.0';
    const avgMs   = reqTotal ? (reqDurMs/reqTotal).toFixed(1) : '0.0';

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Demo App ${VERSION}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',system-ui,sans-serif;
     background:linear-gradient(135deg,#0d0d1a 0%,#1a0a2e 50%,#0d0d1a 100%);
     min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.card{background:rgba(255,255,255,0.04);backdrop-filter:blur(24px);
      border:1px solid rgba(147,51,234,0.25);border-radius:24px;
      padding:44px 52px;max-width:580px;width:100%;color:#fff;
      box-shadow:0 32px 64px rgba(147,51,234,0.15),0 0 0 1px rgba(147,51,234,0.1)}
.track-badge{display:inline-flex;align-items:center;gap:8px;
  background:rgba(147,51,234,0.15);border:1px solid rgba(147,51,234,0.5);
  color:#c084fc;font-size:11px;font-weight:700;letter-spacing:1.5px;
  padding:6px 16px;border-radius:20px;margin-bottom:24px;text-transform:uppercase}
.dot{width:8px;height:8px;border-radius:50%;background:#c084fc;
     box-shadow:0 0 10px #c084fc;animation:pulse 1.5s infinite}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:0.5;transform:scale(1.3)}}
h1{font-size:2.2rem;font-weight:800;margin-bottom:6px;
   background:linear-gradient(90deg,#c084fc,#f472b6);
   -webkit-background-clip:text;-webkit-text-fill-color:transparent}
.version{color:#6b7280;font-size:0.9rem;margin-bottom:28px;font-family:monospace}
.new-badge{display:inline-block;background:rgba(245,158,11,0.2);
  border:1px solid rgba(245,158,11,0.4);color:#fbbf24;
  font-size:10px;padding:2px 8px;border-radius:6px;margin-left:8px;font-weight:600}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:28px}
.stat{background:rgba(255,255,255,0.04);border-radius:14px;padding:18px 16px;
      text-align:center;border:1px solid rgba(147,51,234,0.15)}
.val{font-size:1.7rem;font-weight:800;color:#c084fc;line-height:1}
.lbl{font-size:10px;color:#4b5563;text-transform:uppercase;letter-spacing:1px;margin-top:6px}
.features{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:24px}
.feat{background:rgba(147,51,234,0.12);border:1px solid rgba(147,51,234,0.2);
  color:#a78bfa;font-size:11px;padding:4px 12px;border-radius:8px}
.footer{display:flex;justify-content:space-between;align-items:center;
  border-top:1px solid rgba(147,51,234,0.1);padding-top:18px;
  font-size:0.78rem;color:#4b5563}
.env-tag{background:rgba(147,51,234,0.15);color:#c084fc;
  padding:3px 10px;border-radius:8px;font-size:10px;font-weight:600;letter-spacing:0.5px}
</style>
</head>
<body>
<div class="card">
  <div class="track-badge"><span class="dot"></span>CANARY RELEASE</div>
  <h1>Demo App <span class="new-badge">NEW</span></h1>
  <div class="version">${VERSION} &nbsp;·&nbsp; Build: ${BUILD}</div>
  <div class="features">
    <span class="feat">🎨 Dark Theme</span>
    <span class="feat">⚡ API v2</span>
    <span class="feat">🔌 WebSocket</span>
    <span class="feat">🗄️ Redis Cache</span>
  </div>
  <div class="grid">
    <div class="stat"><div class="val">${reqTotal}</div><div class="lbl">Requests</div></div>
    <div class="stat"><div class="val">${upSec()}s</div><div class="lbl">Uptime</div></div>
    <div class="stat"><div class="val">${errRate}%</div><div class="lbl">Error Rate</div></div>
    <div class="stat"><div class="val">${avgMs}ms</div><div class="lbl">Avg Latency</div></div>
  </div>
  <div class="footer">
    <span>${os.hostname()}</span>
    <span class="env-tag">${ENV}</span>
    <span>${now()}</span>
  </div>
</div>
</body></html>`;

    done(200);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  }, extraLatency);
});

// ── Graceful shutdown ─────────────────────────────────────────────────────────
['SIGTERM','SIGINT'].forEach(sig => process.on(sig, () => {
  log('warn', `Received ${sig} — shutting down gracefully`);
  server.close(() => { log('info', 'HTTP server closed'); process.exit(0); });
  setTimeout(() => { log('error', 'Forced exit after timeout'); process.exit(1); }, 10_000);
}));

server.listen(PORT, '0.0.0.0', () => log('info', `Listening on :${PORT}`));
