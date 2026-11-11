const http = require('node:http');
const { spawn, execFileSync } = require('node:child_process');
const path = require('node:path');

const gitBackend = path.join(
  execFileSync('git', ['--exec-path'], { encoding: 'utf8' }).trim(),
  'git-http-backend',
);

const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://git-fixture.invalid');
  if (url.pathname === '/healthz') {
    response.writeHead(200, { 'content-type': 'text/plain' }).end('ok');
    return;
  }
  if (!url.pathname.startsWith('/audio.git/')) {
    response.writeHead(404).end();
    return;
  }

  const backend = spawn(gitBackend, [], {
    env: {
      ...process.env,
      GIT_PROJECT_ROOT: process.env.GIT_PROJECT_ROOT || '/repos',
      GIT_HTTP_EXPORT_ALL: '1',
      PATH_INFO: url.pathname,
      QUERY_STRING: url.search.slice(1),
      REQUEST_METHOD: request.method,
      CONTENT_TYPE: request.headers['content-type'] || '',
      CONTENT_LENGTH: request.headers['content-length'] || '',
      HTTP_GIT_PROTOCOL: request.headers['git-protocol'] || '',
      SCRIPT_NAME: '',
      REMOTE_ADDR: request.socket.remoteAddress || '',
      SERVER_PROTOCOL: `HTTP/${request.httpVersion}`,
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let headerBuffer = Buffer.alloc(0);
  let responseStarted = false;
  backend.stdout.on('data', (chunk) => {
    if (responseStarted) {
      response.write(chunk);
      return;
    }
    headerBuffer = Buffer.concat([headerBuffer, chunk]);
    const boundary = headerBuffer.indexOf('\r\n\r\n');
    if (boundary < 0) return;

    const headers = {};
    let status = 200;
    for (const line of headerBuffer.subarray(0, boundary).toString('utf8').split('\r\n')) {
      const colon = line.indexOf(':');
      if (colon < 0) continue;
      const name = line.slice(0, colon).trim();
      const value = line.slice(colon + 1).trim();
      if (name.toLowerCase() === 'status') status = Number.parseInt(value, 10) || 200;
      else headers[name] = value;
    }
    response.writeHead(status, headers);
    responseStarted = true;
    response.write(headerBuffer.subarray(boundary + 4));
    headerBuffer = Buffer.alloc(0);
  });
  backend.stderr.on('data', (chunk) => process.stderr.write(chunk));
  backend.on('close', (code) => {
    if (!responseStarted) response.writeHead(code === 0 ? 204 : 500);
    response.end();
  });
  request.pipe(backend.stdin);
  request.on('aborted', () => backend.kill());
});

server.listen(Number(process.env.PORT || 8080), process.env.HOST || '0.0.0.0');
