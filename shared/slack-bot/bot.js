#!/usr/bin/env node
/**
 * Maia Slack Bot — Socket Mode
 *
 * Runs locally as a systemd service. Each Slack thread is an isolated
 * AI session using stream-json input for persistent processes.
 * Follow-up messages are queued and piped into the active process's stdin
 * instead of spawning duplicate processes.
 *
 * Features:
 * - Persistent streaming processes per session (multi-turn via stdin)
 * - Thread-to-session mapping with resume support (Claude Code)
 * - Live tool-use status updates via Slack assistant API
 * - File upload/download support
 * - Long response chunking
 * - Graceful shutdown with in-flight request tracking
 * - Self-restart via [RESTART] marker
 * - Slash commands: /clear, /context, /workers, /spawn, /restart
 *
 * Environment variables (in .env):
 *   SLACK_BOT_TOKEN    — xoxb-... Bot User OAuth Token
 *   SLACK_APP_TOKEN    — xapp-... App-Level Token (Socket Mode)
 *   ENGINE             — "claude" or "codex" (default: auto-detect)
 *   CONFIG_PATH        — path to config.json (default: ~/agent-setup/config.json)
 */

'use strict';

require('dotenv').config({ path: __dirname + '/.env' });

const { App } = require('@slack/bolt');
const { spawn, execFile, execSync } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const https = require('https');
const http = require('http');

// ---------------------------------------------------------------------------
// Load config
// ---------------------------------------------------------------------------
const CONFIG_PATH = process.env.CONFIG_PATH || path.join(os.homedir(), 'agent-setup', 'config.json');
let config = {};
try { config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch {}

const ASSISTANT_NAME = config.assistant?.name || 'Agent';
const USER_NAME = config.user?.name || 'User';
const AGENT_DIR = (config.paths?.agent_dir || '~/.agent').replace(/^~/, os.homedir());

// ---------------------------------------------------------------------------
// Detect engine
// ---------------------------------------------------------------------------
function detectEngine() {
  const configured = process.env.ENGINE || config.engine;
  if (configured === 'codex') return 'codex';
  if (configured === 'claude' || configured === 'claude-code') return 'claude';
  try {
    execSync('which claude', { stdio: 'ignore' });
    return 'claude';
  } catch {
    try {
      execSync('which codex', { stdio: 'ignore' });
      return 'codex';
    } catch {
      console.error('No AI engine found. Install Claude Code or Codex CLI.');
      process.exit(1);
    }
  }
}

const ENGINE = detectEngine();
console.log(`[agent-slack] Engine: ${ENGINE}`);

// ---------------------------------------------------------------------------
// Channel config — reads from config.json, keyed by channel name
// Users define channels in config.json under slack.channels.
// ---------------------------------------------------------------------------
const CHANNEL_CONFIG = {};
if (config.slack?.channels) {
  for (const [name, cfg] of Object.entries(config.slack.channels)) {
    CHANNEL_CONFIG[name] = {
      workdir: (cfg.workdir || '~').replace(/^~/, os.homedir()),
      systemPrompt: (cfg.system_prompt || `You are ${ASSISTANT_NAME}, ${USER_NAME}'s AI assistant.`)
        .replace(/\{\{ASSISTANT_NAME\}\}/g, ASSISTANT_NAME)
        .replace(/\{\{USER_NAME\}\}/g, USER_NAME),
    };
  }
}

const DEFAULT_CONFIG = {
  workdir: os.homedir(),
  systemPrompt: `You are ${ASSISTANT_NAME}, ${USER_NAME}'s AI assistant. Handle any request.`,
};

// Appended to every prompt — enforces Slack-compatible output
const SLACK_FORMATTING = `
--- Slack Formatting Rules (ALWAYS follow these) ---
Your response will be posted directly to Slack. Slack uses mrkdwn, NOT standard markdown.
- Use *bold* for emphasis (not **bold**)
- Use _italic_ for italics (not *italic*)
- Use \`inline code\` for code snippets
- Use \`\`\`code blocks\`\`\` for multi-line code
- Bullet lists: use - or • at the start of lines
- NEVER use markdown tables (| col | col | format). Slack does not render them and they look broken. Always use labeled lines or bullet lists instead. This is a hard rule — no exceptions.
- NO # headers — use *bold text* as section labels instead
- NO HTML tags
- Keep responses concise — this is a chat interface`;

// ---------------------------------------------------------------------------
// Session store — key → claude session_id, persisted to disk
// ---------------------------------------------------------------------------
const SESSIONS_FILE = path.join(__dirname, 'sessions.json');

function loadSessions() {
  try {
    const data = JSON.parse(fs.readFileSync(SESSIONS_FILE, 'utf8'));
    return new Map(Object.entries(data));
  } catch {
    return new Map();
  }
}

function saveSessions(map) {
  try {
    fs.writeFileSync(SESSIONS_FILE, JSON.stringify(Object.fromEntries(map), null, 2));
  } catch (err) {
    console.error('[agent-slack] Failed to save sessions:', err.message);
  }
}

const sessions = loadSessions();
console.log(`[agent-slack] Loaded ${sessions.size} persisted session(s)`);

// Track consecutive failures per session key — auto-reset after MAX_FAILURES
const sessionFailures = new Map();
const MAX_SESSION_FAILURES = 2;

// ---------------------------------------------------------------------------
// Channel name cache
// ---------------------------------------------------------------------------
const channelCache = new Map();

async function resolveChannelName(client, channelId) {
  if (channelCache.has(channelId)) return channelCache.get(channelId);
  try {
    const res = await client.conversations.info({ channel: channelId });
    const name = res.channel?.name || '';
    channelCache.set(channelId, name);
    return name;
  } catch {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Streaming claude processes — persistent per session key
// Uses --input-format stream-json to keep processes alive between turns.
// Follow-up messages are queued and piped into stdin instead of spawning
// duplicate processes.
// ---------------------------------------------------------------------------
const activeProcesses = new Map();
const STREAM_IDLE_TIMEOUT = 10 * 60 * 1000; // 10 min — close idle processes

function createStreamingProcess(sessionKey, sessionId, workdir) {
  let cmd, args;

  if (ENGINE === 'claude') {
    cmd = 'claude';
    args = [
      '-p',
      '--dangerously-skip-permissions',
      '--input-format', 'stream-json',
      '--output-format', 'stream-json',
      '--verbose',
    ];
    if (sessionId) args.push('--resume', sessionId);
  } else {
    // Codex doesn't support stream-json — fall back to single-turn
    cmd = 'codex';
    args = ['--approval-mode', 'full-auto'];
  }

  // Strip agent session markers to prevent nested-session SIGTERM
  const env = { ...process.env };
  delete env.CLAUDECODE;
  delete env.CLAUDE_CODE_ENTRYPOINT;

  const proc = spawn(cmd, args, {
    cwd: workdir,
    env,
    stdio: ['pipe', 'pipe', 'pipe'],
    detached: true,
  });

  const entry = {
    proc,
    sessionId: sessionId || null,
    sessionKey,
    turnQueue: [],
    currentTurn: null,
    buffer: '',
    idleTimer: null,
  };

  // Parse stdout stream-json events (Claude Code)
  proc.stdout.on('data', (chunk) => {
    if (ENGINE !== 'claude') {
      // Codex: accumulate raw text
      entry.buffer += chunk.toString();
      return;
    }
    entry.buffer += chunk.toString();
    const lines = entry.buffer.split('\n');
    entry.buffer = lines.pop(); // hold incomplete line
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const event = JSON.parse(line);
        if (event.type === 'result') {
          entry.sessionId = event.session_id || entry.sessionId;
          let text = event.result || '';
          if (!text && event.is_error) {
            const errMsg = event.errors?.join('; ') || event.error || 'unknown';
            // Session not found — flag for immediate fresh retry
            if (errMsg.includes('No conversation found')) {
              text = '__SESSION_EXPIRED__';
            } else {
              text = `[Error] ${errMsg}`;
            }
          }
          if (entry.currentTurn) {
            entry.currentTurn.resolve({ text, sessionId: entry.sessionId });
            entry.currentTurn = null;
            drainQueue(entry);
          }
        } else if (event.type === 'tool_use' && entry.currentTurn?.onToolUse) {
          entry.currentTurn.onToolUse(event.name, event.input || {});
        }
      } catch {}
    }
  });

  proc.stderr.on('data', () => {}); // drain stderr

  proc.on('close', (code, signal) => {
    activeProcesses.delete(sessionKey);
    clearTimeout(entry.idleTimer);
    const killed = code === 143 || signal === 'SIGTERM';

    // For Codex: resolve with accumulated buffer
    if (ENGINE !== 'claude' && entry.currentTurn) {
      entry.currentTurn.resolve({
        text: entry.buffer.trim(),
        sessionId: entry.sessionId,
        killed,
      });
      entry.currentTurn = null;
    }

    // Resolve current turn if any (Claude)
    if (entry.currentTurn) {
      const exitInfo = signal ? `signal ${signal}` : `code ${code}`;
      entry.currentTurn.resolve({
        text: killed ? '' : `[process exited: ${exitInfo}]`,
        sessionId: entry.sessionId,
        killed,
      });
      entry.currentTurn = null;
    }
    // Resolve queued turns as killed — they'll be retried via new process
    for (const turn of entry.turnQueue) {
      turn.resolve({ text: '', sessionId: entry.sessionId, killed: true });
    }
    entry.turnQueue = [];
    console.log(`[agent-slack] streaming process closed for ${sessionKey} (code=${code}, signal=${signal})`);
  });

  proc.on('error', (err) => {
    activeProcesses.delete(sessionKey);
    clearTimeout(entry.idleTimer);
    if (entry.currentTurn) {
      entry.currentTurn.resolve({
        text: `[Failed to start ${ENGINE}: ${err.message}]`,
        sessionId: entry.sessionId,
      });
      entry.currentTurn = null;
    }
  });

  activeProcesses.set(sessionKey, entry);
  resetIdleTimer(entry);
  console.log(`[agent-slack] spawned streaming process for ${sessionKey} (resume=${sessionId || 'none'})`);
  return entry;
}

function resetIdleTimer(entry) {
  clearTimeout(entry.idleTimer);
  entry.idleTimer = setTimeout(() => {
    console.log(`[agent-slack] idle timeout — closing streaming process for ${entry.sessionKey}`);
    try { entry.proc.stdin.end(); } catch {}
  }, STREAM_IDLE_TIMEOUT);
}

function drainQueue(entry) {
  if (entry.turnQueue.length === 0) {
    resetIdleTimer(entry);
    return;
  }
  const turn = entry.turnQueue.shift();
  entry.currentTurn = turn;

  if (ENGINE === 'claude') {
    const msg = JSON.stringify({
      type: 'user',
      message: { role: 'user', content: turn.prompt },
    }) + '\n';
    try {
      entry.proc.stdin.write(msg);
    } catch (err) {
      turn.resolve({ text: `[stdin write failed: ${err.message}]`, sessionId: entry.sessionId });
      entry.currentTurn = null;
      drainQueue(entry);
    }
  } else {
    // Codex: write prompt as plain text and close stdin (single-turn)
    try {
      entry.proc.stdin.write(turn.prompt);
      entry.proc.stdin.end();
    } catch (err) {
      turn.resolve({ text: `[stdin write failed: ${err.message}]`, sessionId: entry.sessionId });
      entry.currentTurn = null;
    }
  }
}

function sendTurn(entry, prompt, onToolUse) {
  return new Promise((resolve) => {
    entry.turnQueue.push({ prompt, onToolUse, resolve });
    if (!entry.currentTurn) {
      drainQueue(entry);
    }
  });
}

// ---------------------------------------------------------------------------
// Tool status — human-readable descriptions for live Slack status
// ---------------------------------------------------------------------------
function toolStatus(name, inp) {
  if (name === 'Bash') {
    const cmd = (inp.command || '').trim();
    return 'running: ' + (cmd.length > 60 ? cmd.slice(0, 60) + '...' : cmd);
  }
  if (name === 'Write') return `writing ${path.basename(inp.file_path || 'file')}`;
  if (name === 'Edit') return `editing ${path.basename(inp.file_path || 'file')}`;
  if (name === 'Read') return `reading ${path.basename(inp.file_path || 'file')}`;
  if (name === 'Glob') return `searching for ${inp.pattern || 'files'}`;
  if (name === 'Grep') return `searching code for "${(inp.pattern || '').slice(0, 40)}"`;
  if (name === 'WebFetch') {
    try { return `fetching ${new URL(inp.url).hostname}`; } catch { return 'fetching a page'; }
  }
  if (name === 'WebSearch') return `searching: ${(inp.query || '').slice(0, 50)}`;
  if (name === 'Agent') return `spawning agent: ${(inp.description || '').slice(0, 50)}`;
  return null;
}

// ---------------------------------------------------------------------------
// File download helper — fetches a Slack private file URL using the bot token
// ---------------------------------------------------------------------------
function downloadSlackFile(url, destPath) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : http;
    const file = fs.createWriteStream(destPath);
    proto.get(url, { headers: { Authorization: `Bearer ${process.env.SLACK_BOT_TOKEN}` } }, (res) => {
      if (res.statusCode !== 200) {
        file.close();
        fs.unlink(destPath, () => {});
        return reject(new Error(`HTTP ${res.statusCode} downloading file`));
      }
      res.pipe(file);
      file.on('finish', () => { file.close(); resolve(); });
      file.on('error', (err) => { fs.unlink(destPath, () => {}); reject(err); });
    }).on('error', (err) => { file.close(); fs.unlink(destPath, () => {}); reject(err); });
  });
}

// ---------------------------------------------------------------------------
// Core message handler
// ---------------------------------------------------------------------------
async function processMessage(client, channelId, sessionKey, threadTs, rawText, slackFiles = []) {
  const text = rawText.replace(/<@[A-Z0-9]+>/g, '').trim();
  if (!text && slackFiles.length === 0) return;

  const channelName = await resolveChannelName(client, channelId);
  const channelConfig = CHANNEL_CONFIG[channelName] || DEFAULT_CONFIG;

  // Download attached files to a temp dir
  const tmpDir = path.join(os.tmpdir(), 'agent-slack-files');
  fs.mkdirSync(tmpDir, { recursive: true });

  const tmpFiles = [];
  const attachedFiles = [];

  for (const file of slackFiles) {
    const ext = file.name ? path.extname(file.name) : '';
    const tmpPath = path.join(tmpDir, `${file.id}${ext}`);
    tmpFiles.push(tmpPath);
    try {
      const downloadUrl = file.url_private_download || file.url_private;
      if (!downloadUrl) { console.warn(`[agent-slack] No download URL for file ${file.id}`); continue; }
      await downloadSlackFile(downloadUrl, tmpPath);
      attachedFiles.push({ path: tmpPath, name: file.name || file.id });
      console.log(`[agent-slack] Downloaded file: ${file.name} → ${tmpPath}`);
    } catch (err) {
      console.error(`[agent-slack] Failed to download file ${file.name}:`, err.message);
    }
  }

  let fileContext = '';
  if (attachedFiles.length > 0) {
    fileContext += '\n\n--- Attached files (use Read tool to access) ---\n' +
      attachedFiles.map(f => `${f.name}: ${f.path}`).join('\n');
  }

  const messageText = text || '(file attached)';

  // Check for an active streaming process for this session
  const existingProcess = activeProcesses.get(sessionKey);
  let entry;
  let prompt;

  if (existingProcess && ENGINE === 'claude') {
    // Follow-up turn on active streaming process — light prompt (context already loaded)
    entry = existingProcess;
    prompt = `--- ${USER_NAME}'s message ---\n${messageText}${fileContext}`;
    console.log(`[agent-slack] queuing follow-up on existing process for ${sessionKey}`);
  } else {
    // No active process — resolve persisted session and spawn new streaming process
    const rawSession = sessions.get(sessionKey) || null;
    let existingSession = null;
    let threadContext = '';

    if (rawSession) {
      if (typeof rawSession === 'string') {
        const failures = sessionFailures.get(sessionKey) || 0;
        if (failures >= MAX_SESSION_FAILURES) {
          console.log(`[agent-slack] session ${rawSession} hit ${failures} consecutive failures — starting fresh`);
          existingSession = null;
          sessionFailures.delete(sessionKey);
          threadContext = '\n\n[Note: Previous session was reset due to repeated failures. Starting fresh.]';
        } else {
          existingSession = rawSession;
        }
      } else if (rawSession.archived) {
        if (rawSession.summaryPath) {
          try {
            const summary = fs.readFileSync(rawSession.summaryPath, 'utf8');
            threadContext = `\n\n--- Previous thread context ---\n${summary}\n--- End of previous context ---`;
          } catch {
            threadContext = '\n\n[Note: This continues a previous conversation. Thread history was archived.]';
          }
        } else {
          threadContext = '\n\n[Note: This continues a previous conversation. Thread history was archived but no summary is available.]';
        }
      }
    }

    // If no session exists and this is a thread reply, fetch the parent message
    // so the new session has context (e.g. cron notifications posted via API)
    if (!rawSession && !sessionKey.endsWith(':im')) {
      try {
        const parentResult = await client.conversations.replies({
          channel: channelId,
          ts: threadTs,
          limit: 1,
          inclusive: true,
        });
        const parentMsg = parentResult.messages?.[0];
        if (parentMsg && parentMsg.text) {
          threadContext = `\n\n--- Original message in this thread ---\n${parentMsg.text}\n--- End of original message ---`;
        }
      } catch (err) {
        console.warn(`[agent-slack] Failed to fetch parent message for thread ${threadTs}:`, err.message);
      }
    }

    console.log(`[agent-slack] message in #${channelName} thread=${threadTs} session=${existingSession || (rawSession?.archived ? 'archived→fresh' : 'new')} files=${slackFiles.length}`);

    entry = createStreamingProcess(sessionKey, existingSession, channelConfig.workdir);
    prompt = `${channelConfig.systemPrompt}${SLACK_FORMATTING}${threadContext}\n\n--- ${USER_NAME}'s message ---\n${messageText}${fileContext}`;
  }

  // Show live Slack loading indicator — updates as tools fire
  let currentStatus = 'is thinking...';
  const setStatus = (status) => {
    currentStatus = status;
    return client.assistant.threads.setStatus({
      channel_id: channelId,
      thread_ts: threadTs,
      status,
    }).catch(() => {});
  };

  await setStatus('is thinking...');
  const statusInterval = setInterval(() => setStatus(currentStatus), 90_000);

  // Send turn to streaming process (queued if a turn is already active)
  let result;
  try {
    result = await sendTurn(entry, prompt, (toolName, toolInput) => {
      const status = toolStatus(toolName, toolInput);
      if (status) setStatus(status);
    });
  } finally {
    clearInterval(statusInterval);
    for (const tmpPath of tmpFiles) {
      fs.unlink(tmpPath, () => {});
    }
  }

  console.log(`[agent-slack] turn done, sessionId=${result.sessionId}, textLen=${result.text.length}${result.killed ? ' (killed)' : ''}`);

  // Session expired — clear stale session and retry immediately with a fresh session
  if (result.text === '__SESSION_EXPIRED__') {
    console.log(`[agent-slack] session expired for ${sessionKey} — clearing and retrying fresh`);
    sessions.delete(sessionKey);
    saveSessions(sessions);
    sessionFailures.delete(sessionKey);
    try { entry.proc.kill('SIGTERM'); } catch {}
    activeProcesses.delete(sessionKey);
    return processMessage(client, channelId, sessionKey, threadTs, rawText, slackFiles);
  }

  // Track session health — increment failures on kill/empty, clear on success
  if (result.killed || (result.text.length === 0 && sessions.has(sessionKey))) {
    const prev = sessionFailures.get(sessionKey) || 0;
    sessionFailures.set(sessionKey, prev + 1);
    console.log(`[agent-slack] session failure #${prev + 1} for ${sessionKey}`);
  } else {
    sessionFailures.delete(sessionKey);
  }

  // Persist session for future follow-ups in this thread (survives restarts)
  if (result.sessionId) {
    sessions.set(sessionKey, result.sessionId);
    saveSessions(sessions);
  }

  // Parse [ATTACH: /path/to/file] markers — the agent uses these to send files back
  const ATTACH_RE = /\[ATTACH:\s*([^\]\n]+)\]/g;
  const attachPaths = [];
  let cleanText = result.text;
  let attachMatch;
  while ((attachMatch = ATTACH_RE.exec(result.text)) !== null) {
    attachPaths.push(attachMatch[1].trim());
  }
  if (attachPaths.length > 0) {
    cleanText = result.text.replace(/\[ATTACH:\s*([^\]\n]+)\]/g, '').trim();
  }

  // Parse [RESTART] marker — agent uses this to request a deferred restart after response posts
  const needsRestart = /\[RESTART\]/.test(cleanText);
  if (needsRestart) {
    cleanText = cleanText.replace(/\[RESTART\]/g, '').trim();
  }

  // Slack max message length is 4000 chars — chunk if needed
  const MAX = 3900;
  const chunks = [];
  for (let i = 0; i < cleanText.length; i += MAX) {
    chunks.push(cleanText.slice(i, i + MAX));
  }
  // If empty (e.g. killed mid-run), post nothing
  if (chunks.length === 0 && attachPaths.length === 0) return;

  try {
    for (const chunk of chunks) {
      if (!chunk.trim()) continue;
      await client.chat.postMessage({
        channel: channelId,
        thread_ts: threadTs,
        text: chunk,
      });
    }
    // Upload any files the agent wants to send back
    for (const filePath of attachPaths) {
      if (!fs.existsSync(filePath)) {
        console.error(`[agent-slack] Attach file not found: ${filePath}`);
        continue;
      }
      try {
        await client.files.uploadV2({
          channel_id: channelId,
          thread_ts: threadTs,
          filename: path.basename(filePath),
          file: fs.createReadStream(filePath),
        });
        console.log(`[agent-slack] Uploaded file: ${filePath}`);
      } catch (err) {
        console.error(`[agent-slack] Failed to upload ${filePath}:`, err.message);
      }
    }
    console.log(`[agent-slack] response posted (${chunks.length} chunk(s), ${attachPaths.length} file(s))`);

    // Deferred restart — triggered by [RESTART] marker in response
    if (needsRestart) {
      console.log('[agent-slack] deferred restart requested — restarting in 1s...');
      setTimeout(() => {
        execFile('systemctl', ['--user', 'restart', 'agent-slack'], (err) => {
          if (err) console.error('[agent-slack] deferred restart failed:', err.message);
        });
      }, 1000);
    }
  } catch (err) {
    console.error('[agent-slack] Failed to post response:', err.message);
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  appToken: process.env.SLACK_APP_TOKEN,
  socketMode: true,
  logLevel: 'warn',
});

// ---------------------------------------------------------------------------
// @mention — starts or continues a thread session
// ---------------------------------------------------------------------------
app.event('app_mention', async ({ event, client }) => {
  if (event.edited) return;
  const threadTs = event.thread_ts || event.ts;
  const key = `${event.channel}:${threadTs}`;
  await trackedProcessMessage(client, event.channel, key, threadTs, event.text, event.files || []);
});

// ---------------------------------------------------------------------------
// Thread follow-ups — no @mention needed once a session exists
// DMs — always respond, one continuous session per DM channel
// ---------------------------------------------------------------------------
app.message(async ({ message, client }) => {
  if (message.bot_id) return;
  if (message.subtype && message.subtype !== 'file_share') return;
  // Mentions are handled by app_mention — avoid double-processing
  if (message.text && /<@[A-Z0-9]+>/.test(message.text)) return;

  const channel = message.channel;
  const text = message.text || '';
  const files = message.files || [];

  // DMs: one persistent session per DM channel (no thread required)
  if (message.channel_type === 'im') {
    const key = `${channel}:im`;
    const threadTs = message.ts;
    await trackedProcessMessage(client, channel, key, threadTs, text, files);
    return;
  }

  // Channel: any message starts or continues a session
  const threadTs = message.thread_ts || message.ts;
  const key = `${channel}:${threadTs}`;
  await trackedProcessMessage(client, channel, key, threadTs, text, files);
});

// ---------------------------------------------------------------------------
// /clear — clear all thread sessions in this channel
// ---------------------------------------------------------------------------
app.command('/clear', async ({ command, ack, respond }) => {
  await ack();
  let count = 0;
  for (const key of sessions.keys()) {
    if (key.startsWith(command.channel_id + ':')) {
      sessions.delete(key);
      count++;
    }
  }
  saveSessions(sessions);
  await respond({
    response_type: 'ephemeral',
    text: `Cleared ${count} active session(s) in this channel.`,
  });
});

// ---------------------------------------------------------------------------
// /context — show channel config and active sessions
// ---------------------------------------------------------------------------
app.command('/context', async ({ command, ack, respond, client }) => {
  await ack();
  const channelName = await resolveChannelName(client, command.channel_id);
  const channelConfig = CHANNEL_CONFIG[channelName] || DEFAULT_CONFIG;
  const active = [...sessions.keys()].filter(k => k.startsWith(command.channel_id + ':')).length;
  await respond({
    response_type: 'ephemeral',
    text: `*Channel:* #${channelName}\n*Workdir:* \`${channelConfig.workdir}\`\n*Active thread sessions:* ${active}`,
  });
});

// ---------------------------------------------------------------------------
// /workers — list background workers
// ---------------------------------------------------------------------------
app.command('/workers', async ({ ack, respond }) => {
  await ack();
  const activeDir = path.join(AGENT_DIR, 'workers', 'active');
  const completedDir = path.join(AGENT_DIR, 'workers', 'completed');
  const lines = [];

  const active = [];
  if (fs.existsSync(activeDir)) {
    for (const fname of fs.readdirSync(activeDir).sort()) {
      if (!fname.endsWith('.json')) continue;
      try {
        const w = JSON.parse(fs.readFileSync(path.join(activeDir, fname), 'utf8'));
        active.push(`- ${w.description} (PID ${w.pid}) — ${w.last_status || 'running...'}`);
      } catch {}
    }
  }
  lines.push(active.length ? `*Active (${active.length}):*\n${active.join('\n')}` : 'No active workers.');

  const completed = [];
  if (fs.existsSync(completedDir)) {
    for (const fname of fs.readdirSync(completedDir).sort().reverse().slice(0, 5)) {
      if (!fname.endsWith('.json')) continue;
      try {
        const w = JSON.parse(fs.readFileSync(path.join(completedDir, fname), 'utf8'));
        completed.push(`- ${w.description} [${w.status}] ${(w.finished_at || '').slice(0, 10)}`);
      } catch {}
    }
  }
  if (completed.length) lines.push(`\n*Recent completed:*\n${completed.join('\n')}`);

  await respond({ response_type: 'ephemeral', text: lines.join('\n') });
});

// ---------------------------------------------------------------------------
// /spawn — spawn a background worker in the channel's workdir
// ---------------------------------------------------------------------------
app.command('/spawn', async ({ command, ack, respond, client }) => {
  await ack();
  const text = command.text.trim();
  if (!text) {
    await respond({ response_type: 'ephemeral', text: 'Usage: /spawn <prompt>' });
    return;
  }
  const channelName = await resolveChannelName(client, command.channel_id);
  const channelConfig = CHANNEL_CONFIG[channelName] || DEFAULT_CONFIG;
  const spawnScript = path.join(AGENT_DIR, 'scripts', 'spawn-worker.sh');
  const description = text.slice(0, 60);

  execFile('/bin/bash', [spawnScript, description, text, channelConfig.workdir], { timeout: 15000 }, async (err, stdout, stderr) => {
    const output = (stdout || stderr || (err ? err.message : 'Worker spawned.')).trim();
    await respond({ response_type: 'ephemeral', text: output });
  });
});

// ---------------------------------------------------------------------------
// /restart — restart the bot service (responds first, then triggers restart)
// ---------------------------------------------------------------------------
app.command('/restart', async ({ ack, respond }) => {
  await ack();
  await respond({ response_type: 'ephemeral', text: 'Restart triggered — back in a moment.' });
  setTimeout(() => {
    execFile('systemctl', ['--user', 'restart', 'agent-slack'], (err) => {
      if (err) console.error('[agent-slack] restart failed:', err.message);
    });
  }, 500);
});

// Global error handler
app.error(async (error) => {
  console.error('[agent-slack] Unhandled Bolt error:', error);
});

// ---------------------------------------------------------------------------
// Graceful shutdown — wait for active processes to finish
// ---------------------------------------------------------------------------
const activeRequests = new Set();

const originalProcessMessage = processMessage;
async function trackedProcessMessage(...args) {
  const p = originalProcessMessage(...args);
  activeRequests.add(p);
  p.finally(() => activeRequests.delete(p));
  return p;
}

async function shutdown(signal) {
  console.log(`[agent-slack] ${signal} received — closing ${activeProcesses.size} streaming process(es), waiting for ${activeRequests.size} active request(s)...`);
  await app.stop();
  // Close all streaming processes gracefully (EOF on stdin)
  for (const [, entry] of activeProcesses) {
    clearTimeout(entry.idleTimer);
    try { entry.proc.stdin.end(); } catch {}
  }
  if (activeRequests.size > 0) {
    await Promise.race([
      Promise.allSettled([...activeRequests]),
      new Promise(r => setTimeout(r, 5 * 60 * 1000)),
    ]);
  }
  console.log('[agent-slack] Shutdown complete.');
  process.exit(0);
}

process.once('SIGTERM', () => shutdown('SIGTERM'));
process.once('SIGINT', () => shutdown('SIGINT'));

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
(async () => {
  await app.start();
  console.log(`[agent-slack] ${ASSISTANT_NAME} bot started in Socket Mode (${ENGINE} engine)`);
})();
