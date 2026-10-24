// Consistency checks between the k8s manifests, the images and the nginx config.
// These catch the "names/ports don't line up" class of bugs before ArgoCD syncs them.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const k8s = (f) => fs.readFileSync(path.join(__dirname, '..', 'k8s', f), 'utf8');

test('backend Service is named "backend" to match the nginx proxy_pass', () => {
  assert.match(k8s('backend-service.yaml'), /^\s*name:\s*backend\s*$/m);
});

test('backend Service targets container port 3000', () => {
  assert.match(k8s('backend-service.yaml'), /targetPort:\s*3000/);
  assert.match(k8s('backend-deployment.yaml'), /containerPort:\s*3000/);
});

test('frontend Service targets the unprivileged nginx port 8080', () => {
  assert.match(k8s('frontend-service.yaml'), /targetPort:\s*8080/);
  assert.match(k8s('frontend-deployment.yaml'), /containerPort:\s*8080/);
});

test('backend ConfigMap points at postgres-service:5432', () => {
  const cm = k8s('configmap.yaml');
  assert.match(cm, /DB_HOST:\s*"postgres-service"/);
  assert.match(cm, /DB_PORT:\s*"5432"/);
  assert.match(k8s('postgres-service.yaml'), /name:\s*postgres-service/);
});

test('deployments use versioned images, never :latest', () => {
  for (const f of ['backend-deployment.yaml', 'frontend-deployment.yaml']) {
    const image = k8s(f).match(/image:\s*(abdirahmankhalif\/\S+)/)[1];
    assert.ok(!image.endsWith(':latest') && image.includes(':'), `${f} uses ${image}`);
  }
});