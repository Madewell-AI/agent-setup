/**
 * Maia Slack Bot — Socket Mode
 *
 * Maps each Slack thread to a persistent AI agent session.
 * Supports both Claude Code and Codex CLI as the engine.
 *
 * Features:
 * - Thread-to-session mapping with resume support
 * - Live tool-use status updates in Slack
 * - File upload/download support
 * - Long response chunking
 * - Graceful shutdown with in-flight request tracking
 * - Self-restart via [RESTART] marker
 *
 * Environment variables (in .env):
 *   SLACK_BOT_TOKEN    — xoxb-... Bot User OAuth Token
 *   SLACK_APP_TOKEN    — xapp-... App-Level Token (Socket Mode)
 *   ENGINE             — "claude" or "codex" (default: auto-detect)
 */

const { WebClient } = require('@slack/web-api');
const { SocketModeClient } = require('@slack/socket-mode');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Load environment
require('dotenv').config({ path: path.join(__dirname, '.env') });

const SLACK_BOT_TOKEN = process.env.SLACK_BOT_TOKEN;
const SLACK_APP_TOKEN = process.env.SLACK_APP_TOKEN;
const CONFIG_PATH = process.env.CONFIG_PATH || path.join(os.homedir(), 'agent-setup', 'config.json');

if (!SLACK_BOT_TOKEN || !SLACK_APP_TOKEN) {
    console.error('Missing SLACK_BOT_TOKEN or SLACK_APP_TOKEN in .env');
    process.exit(1);
}

const web = new WebClient(SLACK_BOT_TOKEN);
const socket = new SocketModeClient({ appToken: SLACK_APP_TOKEN });

// Session state
const SESSIONS_FILE = path.join(__dirname, 'sessions.json');
let sessions = {};
if (fs.existsSync(SESSIONS_FILE)) {
    try { sessions = JSON.parse(fs.readFileSync(SESSIONS_FILE, 'utf8')); } catch (e) { sessions = {}; }
}
const saveSessions = () => fs.writeFileSync(SESSIONS_FILE, JSON.stringify(sessions, null, 2));

// Active requests tracking (for graceful shutdown)
let activeRequests = 0;
let shuttingDown = false;

// Load config
let config = {};
try { config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch (e) {}

const ASSISTANT_NAME = config.assistant?.name || 'Agent';
const USER_NAME = config.user?.name || 'User';

// Detect engine
function detectEngine() {
    const configured = process.env.ENGINE || config.engine;
    if (configured === 'codex') return 'codex';
    if (configured === 'claude') return 'claude';

    // Auto-detect
    try {
        require('child_process').execSync('which claude', { stdio: 'ignore' });
        return 'claude';
    } catch {
        try {
            require('child_process').execSync('which codex', { stdio: 'ignore' });
            return 'codex';
        } catch {
            console.error('No AI engine found. Install Claude Code or Codex CLI.');
            process.exit(1);
        }
    }
}

const ENGINE = detectEngine();
console.log(`Engine: ${ENGINE}`);

// Channel configuration
const channelConfigs = {};
if (config.slack?.channels) {
    for (const [name, cfg] of Object.entries(config.slack.channels)) {
        if (cfg.channel_id) {
            channelConfigs[cfg.channel_id] = {
                workdir: (cfg.workdir || '~').replace('~', os.homedir()),
                systemPrompt: (cfg.system_prompt || '')
                    .replace(/\{\{ASSISTANT_NAME\}\}/g, ASSISTANT_NAME)
                    .replace(/\{\{USER_NAME\}\}/g, USER_NAME)
            };
        }
    }
}

// Default config for unconfigured channels
const defaultConfig = {
    workdir: os.homedir(),
    systemPrompt: `You are ${ASSISTANT_NAME}, ${USER_NAME}'s AI assistant.`
};

function getChannelConfig(channelId) {
    return channelConfigs[channelId] || defaultConfig;
}

// Session key: channelId:threadTs or channelId:im
function sessionKey(channelId, threadTs) {
    return threadTs ? `${channelId}:${threadTs}` : `${channelId}:im`;
}

// Slack formatting rules appended to every message
const SLACK_RULES = `
--- Slack Formatting Rules (ALWAYS follow these) ---
Your response will be posted directly to Slack. Slack uses mrkdwn, NOT standard markdown.
- Use *bold* for emphasis (not **bold**)
- Use _italic_ for italics (not *italic*)
- Use \`inline code\` for code snippets
- Use \`\`\`code blocks\`\`\` for multi-line code
- Bullet lists: use - or • at the start of lines
- NEVER use markdown tables. Use labeled lines or bullet lists instead.
- NO # headers — use *bold text* as section labels instead
- NO HTML tags
- Keep responses concise — this is a chat interface
`;

// Send a message to Slack (handles chunking for long messages)
async function sendMessage(channel, text, threadTs) {
    const MAX_LEN = 3900;
    const chunks = [];

    if (text.length <= MAX_LEN) {
        chunks.push(text);
    } else {
        // Split on paragraph boundaries
        let remaining = text;
        while (remaining.length > 0) {
            if (remaining.length <= MAX_LEN) {
                chunks.push(remaining);
                break;
            }
            let splitIdx = remaining.lastIndexOf('\n\n', MAX_LEN);
            if (splitIdx < MAX_LEN * 0.3) splitIdx = remaining.lastIndexOf('\n', MAX_LEN);
            if (splitIdx < MAX_LEN * 0.3) splitIdx = MAX_LEN;
            chunks.push(remaining.slice(0, splitIdx));
            remaining = remaining.slice(splitIdx).trimStart();
        }
    }

    let lastTs = null;
    for (const chunk of chunks) {
        const result = await web.chat.postMessage({
            channel,
            text: chunk,
            thread_ts: threadTs,
            unfurl_links: false,
            unfurl_media: false
        });
        lastTs = result.ts;
    }
    return lastTs;
}

// Update a status message
async function updateStatus(channel, ts, text) {
    try {
        await web.chat.update({ channel, ts, text });
    } catch (e) {
        // Status updates are best-effort
    }
}

// Download a Slack file to temp directory
async function downloadFile(file) {
    const tmpDir = path.join(os.tmpdir(), 'agent-slack-files');
    fs.mkdirSync(tmpDir, { recursive: true });
    const filePath = path.join(tmpDir, file.name || `file-${Date.now()}`);

    const response = await fetch(file.url_private, {
        headers: { Authorization: `Bearer ${SLACK_BOT_TOKEN}` }
    });
    const buffer = Buffer.from(await response.arrayBuffer());
    fs.writeFileSync(filePath, buffer);
    return filePath;
}

// Run the AI agent and stream results
function runAgent(prompt, workdir, sessionId) {
    return new Promise((resolve, reject) => {
        let args;
        let cmd;

        if (ENGINE === 'claude') {
            cmd = 'claude';
            args = ['-p', '--dangerously-skip-permissions', '--output-format', 'stream-json', '--verbose'];
            if (sessionId) {
                args.push('--resume', sessionId);
            }
        } else {
            cmd = 'codex';
            args = ['--approval-mode', 'full-auto'];
            // Codex doesn't have session resume - context is in AGENTS.md memory
        }

        const proc = spawn(cmd, args, {
            cwd: workdir,
            env: { ...process.env, HOME: os.homedir() },
            stdio: ['pipe', 'pipe', 'pipe']
        });

        let output = '';
        let newSessionId = sessionId;
        let toolUpdates = [];

        proc.stdout.on('data', (data) => {
            const text = data.toString();

            if (ENGINE === 'claude') {
                // Parse stream-json events
                for (const line of text.split('\n').filter(l => l.trim())) {
                    try {
                        const event = JSON.parse(line);
                        if (event.type === 'result') {
                            output = event.result || '';
                            if (event.session_id) newSessionId = event.session_id;
                        } else if (event.type === 'tool_use') {
                            toolUpdates.push(event.tool || event.name || 'working');
                        }
                    } catch (e) {
                        // Not JSON, append as raw text
                        output += text;
                    }
                }
            } else {
                // Codex outputs plain text
                output += text;
            }
        });

        let stderr = '';
        proc.stderr.on('data', (data) => { stderr += data.toString(); });

        proc.stdin.write(prompt);
        proc.stdin.end();

        proc.on('close', (code) => {
            resolve({
                output: output.trim(),
                sessionId: newSessionId,
                toolUpdates,
                exitCode: code,
                stderr
            });
        });

        proc.on('error', reject);
    });
}

// Handle incoming messages
async function handleMessage(event) {
    if (shuttingDown) return;
    if (event.bot_id || event.subtype) return; // Ignore bot messages

    const { channel, thread_ts, ts, text, files } = event;
    const threadTs = thread_ts || ts;
    const key = sessionKey(channel, threadTs);
    const channelCfg = getChannelConfig(channel);

    activeRequests++;

    try {
        // Post a "thinking" status
        const statusResult = await web.chat.postMessage({
            channel,
            text: ':hourglass_flowing_sand: Thinking...',
            thread_ts: threadTs
        });
        const statusTs = statusResult.ts;

        // Handle file attachments
        let fileContext = '';
        if (files && files.length > 0) {
            for (const file of files) {
                try {
                    const localPath = await downloadFile(file);
                    fileContext += `\n[Attached file: ${localPath}]`;
                } catch (e) {
                    fileContext += `\n[Failed to download file: ${file.name}]`;
                }
            }
        }

        // Build the full prompt
        const systemPrompt = channelCfg.systemPrompt;
        const fullPrompt = `${systemPrompt}\n${SLACK_RULES}\n--- ${USER_NAME}'s message ---\n${text}${fileContext}`;

        // Get or create session
        const existingSession = sessions[key];
        const sessionId = existingSession?.sessionId || null;

        // Run the agent
        await updateStatus(channel, statusTs, ':gear: Working...');

        const result = await runAgent(fullPrompt, channelCfg.workdir, sessionId);

        // Save session
        sessions[key] = {
            sessionId: result.sessionId,
            channel,
            threadTs,
            lastActivity: new Date().toISOString(),
            consecutiveFailures: result.exitCode !== 0 ? (existingSession?.consecutiveFailures || 0) + 1 : 0
        };

        // Reset session after 2 consecutive failures
        if (sessions[key].consecutiveFailures >= 2) {
            delete sessions[key];
        }

        saveSessions();

        // Delete status message
        try { await web.chat.delete({ channel, ts: statusTs }); } catch (e) {}

        // Send response
        let response = result.output || '(No response generated)';

        // Check for [RESTART] marker
        const needsRestart = response.includes('[RESTART]');
        response = response.replace(/\[RESTART\]/g, '').trim();

        // Check for [ATTACH: path] markers
        const attachRegex = /\[ATTACH:\s*(.+?)\]/g;
        let match;
        const attachments = [];
        while ((match = attachRegex.exec(response)) !== null) {
            attachments.push(match[1].trim());
        }
        response = response.replace(attachRegex, '').trim();

        // Send the text response
        if (response) {
            await sendMessage(channel, response, threadTs);
        }

        // Upload any attachments
        for (const filePath of attachments) {
            if (fs.existsSync(filePath)) {
                try {
                    await web.files.uploadV2({
                        channel_id: channel,
                        thread_ts: threadTs,
                        file: fs.createReadStream(filePath),
                        filename: path.basename(filePath)
                    });
                } catch (e) {
                    await sendMessage(channel, `(Failed to upload: ${path.basename(filePath)})`, threadTs);
                }
            }
        }

        // Handle deferred restart
        if (needsRestart) {
            console.log('Restart requested — restarting in 1 second...');
            setTimeout(() => process.exit(0), 1000);
        }

    } catch (error) {
        console.error('Error handling message:', error);
        try {
            await sendMessage(channel, `Error: ${error.message}`, threadTs);
        } catch (e) {}
    } finally {
        activeRequests--;
    }
}

// Slash commands
async function handleSlashCommand(event, channel, threadTs) {
    const text = event.text?.trim() || '';

    if (text === '/clear') {
        // Clear sessions for this channel
        for (const key of Object.keys(sessions)) {
            if (key.startsWith(`${channel}:`)) {
                delete sessions[key];
            }
        }
        saveSessions();
        await sendMessage(channel, 'Sessions cleared for this channel.', threadTs);
        return true;
    }

    if (text === '/workers') {
        const activeDir = path.join(os.homedir(), '.agent', 'workers', 'active');
        let workerList = 'No active workers.';
        if (fs.existsSync(activeDir)) {
            const files = fs.readdirSync(activeDir).filter(f => f.endsWith('.json'));
            if (files.length > 0) {
                const workers = files.map(f => {
                    const data = JSON.parse(fs.readFileSync(path.join(activeDir, f), 'utf8'));
                    return `- ${data.description} (${data.id})`;
                });
                workerList = `*Active workers:*\n${workers.join('\n')}`;
            }
        }
        await sendMessage(channel, workerList, threadTs);
        return true;
    }

    return false;
}

// Socket Mode event handler
socket.on('message', async ({ event, ack }) => {
    await ack();

    if (event.type === 'message' && event.text) {
        // Check for slash commands first
        const isCommand = await handleSlashCommand(event, event.channel, event.thread_ts || event.ts);
        if (!isCommand) {
            await handleMessage(event);
        }
    }
});

// Graceful shutdown
async function shutdown(signal) {
    console.log(`${signal} received. Waiting for ${activeRequests} active requests...`);
    shuttingDown = true;

    const timeout = setTimeout(() => {
        console.log('Shutdown timeout — forcing exit');
        process.exit(1);
    }, 5 * 60 * 1000); // 5 minute timeout

    const check = setInterval(() => {
        if (activeRequests === 0) {
            clearInterval(check);
            clearTimeout(timeout);
            console.log('All requests complete. Exiting.');
            process.exit(0);
        }
    }, 1000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Start
(async () => {
    await socket.start();
    console.log(`[Maia] ${ASSISTANT_NAME} Slack bot is running (${ENGINE} engine)`);
})();
