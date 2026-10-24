// Static checks on the Express API (no database needed in CI).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const serverPath = path.join(root, 'backend/src/server.js');
const server = fs.readFileSync(serverPath, 'utf8');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'backend/package.json'), 'utf8'));

test('server.js has valid JavaScript syntax', () => {
  execFileSync(process.execPath, ['--check', serverPath]);
});

test('backend declares its runtime dependencies', () => {
  for (const dep of ['express', 'pg', 'cors']) {
    assert.ok(pkg.dependencies[dep], `Missing dependency: ${dep}`);
  }
});

test('backend exposes a /health endpoint', () => {
  assert.ok(server.includes("app.get('/health'"), 'Missing /health route');
});

for (const [method, route] of [
  ['get', '/api/students'],
  ['post', '/api/students'],
  ['get', '/api/grades'],
  ['post', '/api/grades'],
]) {
  test(`backend defines ${method.toUpperCase()} ${route}`, () => {
    assert.ok(server.includes(`app.${method}('${route}'`), `Missing ${method.toUpperCase()} ${route}`);
  });
}

test('backend reads DB settings from the environment', () => {
  for (const v of ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD']) {
    assert.ok(server.includes(`process.env.${v}`), `Missing env var ${v}`);
  }
});