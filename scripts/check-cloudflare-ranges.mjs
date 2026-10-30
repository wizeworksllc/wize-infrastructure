#!/usr/bin/env node
// Do Caddy and the platform's code trust the SAME Cloudflare ranges?
//
// Caddy (k8s/ingress/Caddyfile, `trusted_proxies static …`) decides which
// X-Forwarded-For hops it keeps. sparx's wizeworks/packages/client-ip
// (`CLOUDFLARE_RANGES`) resolves the same chain inside every service and app.
// If Caddy trusts a range the code does not, that Cloudflare edge becomes
// every visitor's address; the other way round, a client can prepend an
// address inside it and be believed.
//
// TWO REPOSITORIES. This was a test inside client-ip that read the Caddyfile
// by relative path. The Caddyfile moved here on 2026-10-29, so the check did
// too, and it runs from BOTH sides — this repo's CI checks out sparx, sparx's CI
// checks out this repo — with:
//
//     node scripts/check-cloudflare-ranges.mjs --sparx <path to a sparx checkout>
//
// The path is required and checked, so a missing checkout fails rather than
// comparing against nothing.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

/** The CIDRs on Caddy's `trusted_proxies static` line, minus the `private_ranges` keyword. */
export function caddyRanges(caddyfile) {
  const line = caddyfile
    .split(/\r?\n/)
    .find((l) => l.trim().startsWith('trusted_proxies static'));
  if (!line) throw new Error('the Caddyfile no longer declares `trusted_proxies static`');
  return line
    .trim()
    .split(/\s+/)
    .slice(2)
    .filter((token) => token !== 'private_ranges');
}

/** The string literals inside `export const CLOUDFLARE_RANGES = [ … ]`. */
export function codeRanges(source) {
  const m = /export const CLOUDFLARE_RANGES\s*=\s*\[([\s\S]*?)\]/.exec(source);
  if (!m) throw new Error('client-ip no longer exports `CLOUDFLARE_RANGES = [...]`');
  const ranges = [...m[1].matchAll(/'([^']+)'|"([^"]+)"/g)].map((r) => r[1] ?? r[2]);
  if (ranges.length === 0) throw new Error('parsed 0 ranges from CLOUDFLARE_RANGES');
  return ranges;
}

/** Ranges only one side trusts. */
export function rangeDrift(caddy, code) {
  const a = new Set(caddy);
  const b = new Set(code);
  return {
    onlyCaddy: [...a].filter((r) => !b.has(r)).sort(),
    onlyCode: [...b].filter((r) => !a.has(r)).sort(),
  };
}

function main() {
  const arg = process.argv.indexOf('--sparx');
  if (arg < 0 || !process.argv[arg + 1]) {
    console.error('usage: node scripts/check-cloudflare-ranges.mjs --sparx <path to a sparx checkout>');
    process.exit(2);
  }
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const clientIp = join(resolve(process.argv[arg + 1]), 'wizeworks/packages/client-ip/src/index.ts');
  if (!existsSync(clientIp)) {
    console.error(`check-cloudflare-ranges: ${clientIp} does not exist. Is --sparx a sparx checkout, or did client-ip move?`);
    process.exit(2);
  }
  const { onlyCaddy, onlyCode } = rangeDrift(
    caddyRanges(readFileSync(join(root, 'k8s/ingress/Caddyfile'), 'utf8')),
    codeRanges(readFileSync(clientIp, 'utf8'))
  );
  if (onlyCaddy.length === 0 && onlyCode.length === 0) {
    return console.log('check-cloudflare-ranges — Caddy and client-ip trust the same ranges.');
  }
  if (onlyCaddy.length) console.error(`only Caddy trusts: ${onlyCaddy.join(' ')}`);
  if (onlyCode.length) console.error(`only client-ip trusts: ${onlyCode.join(' ')}`);
  console.error('Change both together: k8s/ingress/Caddyfile here, wizeworks/packages/client-ip in sparx.');
  process.exit(1);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) main();
