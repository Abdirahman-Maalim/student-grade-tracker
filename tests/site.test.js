// Static checks on the frontend: the UI and the nginx reverse proxy.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

const html = read('frontend/src/index.html');
const nginx = read('frontend/nginx.conf');

test('index.html has the expected title', () => {
  assert.ok(html.includes('<title>Student Grade Tracker</title>'), 'Missing expected title');
});

test('frontend calls the API through the relative /api path', () => {
  assert.ok(html.includes("const API = '/api'"), 'Frontend must call /api so nginx can proxy it');
});

test('nginx listens on 8080 (nginx-unprivileged)', () => {
  assert.match(nginx, /listen\s+8080;/);
});

test('nginx proxies /api/ to the backend Service on 3000', () => {
  assert.match(nginx, /proxy_pass\s+http:\/\/backend:3000\/api\/;/);
});

test('nginx exposes /healthz for container health checks', () => {
  assert.match(nginx, /location \/healthz/);
});