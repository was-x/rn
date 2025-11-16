FROM node:18-alpine

WORKDIR /app

RUN cat > package.json << 'EOF'
{
  "name": "v2ray-edge",
  "version": "1.0.0",
  "dependencies": {
    "ws": "^8.13.0"
  }
}
EOF

RUN mkdir -p dist/apps/node-vless && \
    cat > dist/apps/node-vless/main.js << 'EOF'
const http = require('http');
const WebSocket = require('ws');

const PORT = process.env.PORT || 10000;
const UUID = process.env.UUID || 'ce6d9073-7085-4cb1-a64d-382489a2af94';

console.log(`🚀 Starting V2ray Edge Server on port ${PORT}`);
console.log(`🔑 UUID: ${UUID}`);

// Convert UUID string to buffer (without dashes)
const expectedUUID = UUID.replace(/-/g, '');
const expectedUUIDBuffer = Buffer.from(expectedUUID, 'hex');

const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('V2ray Edge Server Running');
});

const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  console.log('✅ Client connected');
  
  ws.on('message', (data) => {
    const buffer = Buffer.from(data);
    console.log(`📦 Received: ${buffer.length} bytes`);
    
    // VLESS protocol: first byte is version, next 16 bytes are UUID
    if (buffer.length >= 17) {
      const version = buffer[0]; // Should be 0x00 for VLESS
      const receivedUUID = buffer.slice(1, 17); // Next 16 bytes are UUID
      
      console.log(`🔍 Version: 0x${version.toString(16)}`);
      console.log(`🔍 Received UUID: ${receivedUUID.toString('hex')}`);
      console.log(`🔍 Expected UUID: ${expectedUUIDBuffer.toString('hex')}`);
      
      if (receivedUUID.equals(expectedUUIDBuffer)) {
        console.log('✅ UUID verification successful!');
        
        // Send VLESS response (version + addon length)
        const response = Buffer.from([0x01, 0x00]);
        ws.send(response);
        console.log('✅ Sent VLESS handshake response');
        
        // Handle subsequent traffic
        ws.on('message', (trafficData) => {
          const trafficBuffer = Buffer.from(trafficData);
          console.log(`🚀 Traffic: ${trafficBuffer.length} bytes`);
          // Echo back for testing
          ws.send(trafficBuffer);
        });
        
      } else {
        console.log('❌ UUID mismatch');
        ws.close(1008, 'Authentication failed');
      }
    } else {
      console.log('❌ Invalid VLESS header length');
      ws.close(1008, 'Invalid header');
    }
  });

  ws.on('close', () => {
    console.log('🔌 Client disconnected');
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server ready!`);
  console.log(`🔗 WebSocket: wss://darkk-tunnell.onrender.com/${UUID}`);
});
EOF

RUN npm install

ENV PORT=10000
ENV UUID=ce6d9073-7085-4cb1-a64d-382489a2af94

EXPOSE 10000

CMD ["node", "./dist/apps/node-vless/main.js"]
