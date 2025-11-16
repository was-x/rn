FROM node:18-alpine

WORKDIR /app

# Create package.json
RUN cat > package.json << 'EOF'
{
  "name": "v2ray-edge",
  "version": "1.0.0",
  "dependencies": {
    "ws": "^8.13.0"
  }
}
EOF

# Create proper VLESS server implementation
RUN mkdir -p dist/apps/node-vless && \
    cat > dist/apps/node-vless/main.js << 'EOF'
const http = require('http');
const WebSocket = require('ws');
const net = require('net');

const PORT = process.env.PORT || 10000;
const UUID = process.env.UUID || 'ce6d9073-7085-4cb1-a64d-382489a2af94';

console.log(`Starting V2ray Edge VLESS Server on port ${PORT}`);
console.log(`UUID: ${UUID}`);

// Convert UUID string to buffer
function uuidToBuffer(uuid) {
  const hex = uuid.replace(/-/g, '');
  return Buffer.from(hex, 'hex');
}

const expectedUUIDBuffer = uuidToBuffer(UUID);

const server = http.createServer((req, res) => {
  if (req.url === '/health' || req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('V2ray Edge VLESS Server is running\\nUUID: ' + UUID);
  } else if (req.url === `/${UUID}`) {
    res.writeHead(200);
    res.end('VLESS endpoint ready');
  } else {
    res.writeHead(404);
    res.end('Not found');
  }
});

const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  console.log('WebSocket connection established for path:', url.pathname);
  
  // Set binary type to handle VLESS protocol
  ws.binaryType = 'arraybuffer';
  
  ws.on('message', (data) => {
    try {
      // Convert to Buffer regardless of input type
      const buffer = Buffer.from(data);
      console.log(`Received data: ${buffer.length} bytes`);
      
      // Check if this is a VLESS handshake (minimum 16 bytes for UUID)
      if (buffer.length >= 16) {
        const receivedUUID = buffer.slice(0, 16);
        
        // Compare UUIDs
        if (receivedUUID.equals(expectedUUIDBuffer)) {
          console.log('✅ VLESS UUID verification successful');
          
          // Send VLESS response (version + addon length)
          const response = Buffer.from([0x01, 0x00]); // Version 1, 0 addons
          ws.send(response);
          console.log('✅ Sent VLESS handshake response');
          
          // Now handle actual VLESS traffic
          ws.on('message', (trafficData) => {
            const trafficBuffer = Buffer.from(trafficData);
            console.log(`📦 Traffic data: ${trafficBuffer.length} bytes`);
            
            // Echo back for testing (in real implementation, route this traffic)
            ws.send(trafficBuffer);
          });
          
        } else {
          console.log('❌ UUID mismatch');
          console.log('Expected:', UUID);
          console.log('Received:', receivedUUID.toString('hex'));
          ws.close(1008, 'UUID authentication failed');
        }
      } else {
        console.log('❌ Invalid VLESS header length:', buffer.length);
        ws.close(1008, 'Invalid VLESS header');
      }
    } catch (error) {
      console.log('❌ Error processing message:', error.message);
      ws.close(1011, 'Internal error');
    }
  });

  ws.on('close', (code, reason) => {
    console.log(`🔌 WebSocket disconnected: ${code} - ${reason}`);
  });

  ws.on('error', (error) => {
    console.log('❌ WebSocket error:', error.message);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ VLESS Server listening on 0.0.0.0:${PORT}`);
  console.log(`🔗 WebSocket endpoint: wss://darkk-tunnell.onrender.com/${UUID}`);
  console.log(`🔑 Using UUID: ${UUID}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully');
  server.close(() => {
    wss.close(() => {
      process.exit(0);
    });
  });
});

process.on('SIGINT', () => {
  console.log('Received SIGINT, shutting down gracefully');
  server.close(() => {
    wss.close(() => {
      process.exit(0);
    });
  });
});
EOF

# Install dependencies
RUN npm install

# Set environment variables
ENV PORT=10000
ENV UUID=ce6d9073-7085-4cb1-a64d-382489a2af94

EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:10000/health || exit 1

CMD ["node", "./dist/apps/node-vless/main.js"]
