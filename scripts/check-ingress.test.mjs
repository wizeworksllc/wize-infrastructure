import { test } from 'node:test';
import assert from 'node:assert/strict';
import { caddyProblems, findDoc, ownershipProblems } from './check-ingress.mjs';

const CADDY_TWO = `apiVersion: apps/v1
kind: Deployment
metadata:
  name: caddy
spec:
  replicas: 2
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
    type: RollingUpdate
  template:
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: caddy
            topologyKey: kubernetes.io/hostname
`;
const CADDY_BEFORE = `apiVersion: apps/v1
kind: Deployment
metadata:
  name: caddy
spec:
  replicas: 1
  strategy:
    type: Recreate
`;

test('finds a document by kind and name', () => {
  const rendered = `kind: Service\nmetadata:\n  name: caddy\n---\n${CADDY_TWO}`;
  assert.match(findDoc(rendered, 'Deployment', 'caddy'), /replicas: 2/);
  assert.equal(findDoc(rendered, 'Deployment', 'nope'), '');
});

test('one caddy pod on Recreate passes while the cert disk is RWO', () => {
  assert.deepEqual(caddyProblems(CADDY_BEFORE), []);
});

test('two co-located caddy pods pass only on Recreate (Multi-Attach hang, 10-26)', () => {
  assert.equal(caddyProblems(CADDY_TWO).length, 1);
  const recreate = CADDY_TWO.replace(/  strategy:[\s\S]*?type: RollingUpdate\n/, '  strategy:\n    type: Recreate\n');
  assert.deepEqual(caddyProblems(recreate), []);
});

test('two caddy pods without the same-node rule fail', () => {
  assert.equal(caddyProblems(CADDY_BEFORE.replace('replicas: 1', 'replicas: 2')).length, 1);
});

test('a render with no caddy at all fails rather than passing blind', () => {
  assert.equal(caddyProblems('kind: Service\nmetadata:\n  name: caddy\n').length, 1);
});

test('a sparx prune label on the ingress fails', () => {
  assert.equal(ownershipProblems('  labels:\n    app.kubernetes.io/managed-by: sparx-release-infra\n').length, 1);
  assert.deepEqual(ownershipProblems('  labels:\n    app.kubernetes.io/managed-by: wize-infrastructure\n'), []);
});
