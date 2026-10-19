// Adds per-provider descriptions to /v1/models for Claude Code's gateway model
// picker, then forwards everything else to the claude-fife router unchanged.
// CLIProxyAPI has no field for model descriptions, and Claude Code's discovery
// rewrite strips any description it cannot get from the gateway response, so
// the label has to be injected in transit.
//
// Usage: node model-labels-proxy.js <labels.json> <listen-port> <upstream-url>
// The labels file is re-read on every /v1/models request, so editing it takes
// effect without a restart. Request bodies are never logged.
const http = require('http');
const fs = require('fs');

const [labelsPath, portArg, upstreamArg] = process.argv.slice(2);
const port = Number(portArg);
const upstream = new URL(upstreamArg || 'http://127.0.0.1:8317');

// Claude Code's gateway discovery rewrites non-Claude model ids to a masked
// form for the picker: "claude-fable-5-dd-" followed by the id reversed.
// Labels are keyed by the real upstream id, so look through the mask.
const MASK_PREFIX = 'claude-fable-5-dd-';

function labelFor(labels, id) {
  if (typeof labels[id] === 'string' && labels[id]) return labels[id];
  if (id.startsWith(MASK_PREFIX)) {
    const real = id.slice(MASK_PREFIX.length).split('').reverse().join('');
    if (typeof labels[real] === 'string' && labels[real]) return labels[real];
  }
  return null;
}

function readLabels() {
  try {
    return JSON.parse(fs.readFileSync(labelsPath, 'utf8'));
  } catch {
    return {};
  }
}

function fail(res, code) {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ type: 'error', error: { type: 'api_error', message: 'labels proxy upstream error' } }));
}

const server = http.createServer((req, res) => {
  const isModels = req.method === 'GET' && req.url.split('?')[0] === '/v1/models';

  if (!isModels) {
    const headers = { ...req.headers, host: upstream.host };
    const proxied = http.request(
      { hostname: upstream.hostname, port: upstream.port, path: req.url, method: req.method, headers },
      (upstreamRes) => {
        res.writeHead(upstreamRes.statusCode, upstreamRes.headers);
        upstreamRes.pipe(res);
      },
    );
    proxied.on('error', () => fail(res, 502));
    req.pipe(proxied);
    return;
  }

  const headers = { ...req.headers, host: upstream.host };
  const proxied = http.request(
    { hostname: upstream.hostname, port: upstream.port, path: req.url, method: 'GET', headers },
    (upstreamRes) => {
      const chunks = [];
      upstreamRes.on('data', (c) => chunks.push(c));
      upstreamRes.on('end', () => {
        let body;
        try {
          body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        } catch {
          res.writeHead(502, { 'content-type': 'application/json' });
          res.end('{"error":"upstream model list was not JSON"}');
          return;
        }
        const labels = readLabels();
        if (Array.isArray(body.data)) {
          for (const model of body.data) {
            const label = labelFor(labels, model.id);
            if (label) model.description = label;
          }
        }
        const out = Buffer.from(JSON.stringify(body));
        const outHeaders = { ...upstreamRes.headers };
        delete outHeaders['content-encoding'];
        delete outHeaders['transfer-encoding'];
        outHeaders['content-length'] = String(out.length);
        res.writeHead(upstreamRes.statusCode, outHeaders);
        res.end(out);
      });
    },
  );
  proxied.on('error', () => fail(res, 502));
  proxied.end();
});

server.listen(port, '127.0.0.1');
