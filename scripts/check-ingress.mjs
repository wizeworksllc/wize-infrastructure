#!/usr/bin/env node
// Does the rendered ingress keep the rule its certificate disk needs? (SI-3)
// Renders k8s/azure with `kubectl kustomize` (client-side only) and checks the
// caddy Deployment. Needs kubectl on PATH, as every CI runner has.
//
// Moved here from sparx's scripts/check-k8s-overlays.mjs with the ingress
// itself on 2026-10-29; sparx's copy keeps only the Piggles rules.
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

/** The rendered document for kind/name, or ''. */
export function findDoc(rendered, kind, name) {
  return rendered.split(/^---$/m).find((d) => new RegExp(`^kind: ${kind}$`, 'm').test(d) && new RegExp(`^  name: ${name}$`, 'm').test(d)) ?? '';
}

/** One rule: a label and the problem text when the predicate fails. */
const rule = (ok, problem) => (ok ? [] : [problem]);

/** Caddy on its RWO cert disk: Recreate, and pods held to one node when more than one (10-26). */
export function caddyProblems(rendered) {
  const d = findDoc(rendered, 'Deployment', 'caddy');
  if (!d) return ['the rendered overlay has no caddy Deployment'];
  const many = !/^  replicas: 1$/m.test(d);
  const sameNode = /podAffinity:[\s\S]*app: caddy[\s\S]*topologyKey: kubernetes\.io\/hostname/.test(d);
  return [
    ...rule(/type: Recreate/.test(d), 'caddy must use Recreate while its cert disk is ReadWriteOnce'),
    ...rule(!many || sameNode, 'more than one caddy pod must share a node (RWO cert disk)'),
  ];
}

/** The ingress must never carry one of sparx's prune labels, or a sparx release deletes it. */
export function ownershipProblems(rendered) {
  return rule(
    !/app\.kubernetes\.io\/managed-by: sparx-release-/.test(rendered),
    "the ingress carries a sparx-release-* label, so a sparx release's --prune can delete it"
  );
}

function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const rendered = execFileSync('kubectl', ['kustomize', path.join(root, 'k8s/azure')], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  const problems = [...caddyProblems(rendered), ...ownershipProblems(rendered)];
  if (problems.length === 0) return console.log('check-ingress — the ingress rules hold.');
  for (const p of problems) console.error(`check-ingress — ${p}`);
  process.exit(1);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) main();
