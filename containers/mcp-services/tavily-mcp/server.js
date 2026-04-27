/**
 * Tavily MCP Server - Dual Transport (stdio + SSE)
 * 
 * Supports two modes:
 * - stdio: Pass-through to @mcptools/mcp-tavily via child process
 * - sse: Spawns tavily as subprocess + bridges stdio↔SSE via mcp-proxy pattern
 */

const express = require('express');
const { spawn } = require('child_process');
const path = require('path');

const MCP_TRANSPORT = process.env.MCP_TRANSPORT || 'sse';
const PORT = parseInt(process.env.PORT || '8000', 10);

// Load API key from file if TAVILY_API_KEY_FILE is set
if (process.env.TAVILY_API_KEY_FILE) {
  const fs = require('fs');
  try {
    process.env.TAVILY_API_KEY = fs.readFileSync(process.env.TAVILY_API_KEY_FILE, 'utf8').trim();
    console.error('Loaded TAVILY_API_KEY from file');
  } catch (e) {
    console.error('Failed to load TAVILY_API_KEY from file:', e.message);
  }
}

// Verify TAVILY_API_KEY is set
if (!process.env.TAVILY_API_KEY) {
  console.error('Warning: TAVILY_API_KEY environment variable is not set');
}

const mcpPath = path.join(__dirname, 'node_modules', '@mcptools', 'mcp-tavily', 'dist', 'index.js');

if (MCP_TRANSPORT === 'stdio') {
  // Direct stdio mode - spawn the MCP server
  console.error('Starting Tavily MCP with STDIO transport...');
  
  const mcp = spawn('node', [mcpPath], {
    stdio: 'inherit',
    env: process.env
  });
  
  mcp.on('exit', (code) => {
    console.error(`Tavily MCP process exited with code ${code}`);
    process.exit(code || 0);
  });
  
  mcp.on('error', (err) => {
    console.error('Failed to start Tavily MCP:', err);
    process.exit(1);
  });
  
} else if (MCP_TRANSPORT === 'sse') {
  // SSE mode - Express server that spawns tavily subprocess per connection
  // and bridges its stdio to SSE transport
  console.error(`Starting Tavily MCP with SSE transport on port ${PORT}...`);
  
  const app = express();
  app.use(express.json());

  // Track active sessions: sessionId -> { process, buffer }
  const sessions = new Map();

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'tavily-mcp' });
  });

  // SSE endpoint - establishes SSE connection and spawns tavily subprocess
  app.get('/sse', (req, res) => {
    const sessionId = Math.random().toString(36).substring(2, 15);
    console.error(`SSE connection established (session: ${sessionId})`);

    // Set SSE headers
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no'
    });

    // Send endpoint event so client knows where to POST messages
    res.write(`event: endpoint\ndata: /message?sessionId=${sessionId}\n\n`);

    // Spawn tavily subprocess
    const tavilyProc = spawn('node', [mcpPath], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env
    });

    let buffer = '';

    // Forward tavily stdout → SSE events
    tavilyProc.stdout.on('data', (data) => {
      buffer += data.toString();
      
      // Process complete JSON-RPC messages (newline-delimited)
      let newlineIdx;
      while ((newlineIdx = buffer.indexOf('\n')) !== -1) {
        const line = buffer.substring(0, newlineIdx).trim();
        buffer = buffer.substring(newlineIdx + 1);
        
        if (line.length > 0) {
          res.write(`event: message\ndata: ${line}\n\n`);
        }
      }
    });

    tavilyProc.stderr.on('data', (data) => {
      console.error(`[tavily:${sessionId}] ${data.toString().trim()}`);
    });
    
    tavilyProc.on('exit', (code) => {
      console.error(`[tavily:${sessionId}] process exited with code ${code}`);
      sessions.delete(sessionId);
      res.end();
    });

    tavilyProc.on('error', (err) => {
      console.error(`[tavily:${sessionId}] process error:`, err);
      sessions.delete(sessionId);
      res.end();
    });

    sessions.set(sessionId, { process: tavilyProc });

    // Cleanup on client disconnect
    req.on('close', () => {
      console.error(`[tavily:${sessionId}] Client disconnected`);
      tavilyProc.kill();
      sessions.delete(sessionId);
    });
  });

  // Message endpoint - receives JSON-RPC and pipes to tavily subprocess stdin
  app.post('/message', (req, res) => {
    const sessionId = req.query.sessionId;
    const session = sessions.get(sessionId);
    
    if (!session) {
      return res.status(400).json({ error: 'Invalid or expired session' });
    }

    const message = JSON.stringify(req.body);
    session.process.stdin.write(message + '\n');
    res.status(202).json({ status: 'accepted' });
  });

  // Start Express server
  app.listen(PORT, '0.0.0.0', () => {
    console.error(`Tavily MCP SSE server listening on http://0.0.0.0:${PORT}`);
    console.error(`SSE endpoint: http://0.0.0.0:${PORT}/sse`);
    console.error(`Health check: http://0.0.0.0:${PORT}/health`);
  });
  
} else {
  console.error(`Unsupported transport: ${MCP_TRANSPORT}`);
  console.error('Supported transports: stdio, sse');
  process.exit(1);
}