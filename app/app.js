const express = require('express');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

// Main endpoint
app.get('/', (req, res) => {
  const hostname = os.hostname();
  const response = {
    message: 'Hello from EKS Demo!',
    hostname: hostname,
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  };
  
  console.log(`Request received - Pod: ${hostname}`);
  res.json(response);
});

app.listen(PORT, () => {
  console.log(`Hello World app listening on port ${PORT}`);
  console.log(`Pod: ${os.hostname()}`);
});

