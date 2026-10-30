import { test } from 'node:test';
import assert from 'node:assert/strict';
import { caddyRanges, codeRanges, rangeDrift } from './check-cloudflare-ranges.mjs';

const CADDY = '\tservers {\n\t\ttrusted_proxies static private_ranges 173.245.48.0/20 2400:cb00::/32\n\t}\n';
const CODE = "export const CLOUDFLARE_RANGES = [\n  '173.245.48.0/20',\n  '2400:cb00::/32',\n];\n";

test('reads both lists, dropping the private_ranges keyword', () => {
  assert.deepEqual(caddyRanges(CADDY), ['173.245.48.0/20', '2400:cb00::/32']);
  assert.deepEqual(codeRanges(CODE), ['173.245.48.0/20', '2400:cb00::/32']);
});

test('identical lists have no drift', () => {
  assert.deepEqual(rangeDrift(caddyRanges(CADDY), codeRanges(CODE)), { onlyCaddy: [], onlyCode: [] });
});

test('a range on one side only is named', () => {
  const drift = rangeDrift(caddyRanges(CADDY), codeRanges(CODE.replace("  '2400:cb00::/32',\n", '')));
  assert.deepEqual(drift, { onlyCaddy: ['2400:cb00::/32'], onlyCode: [] });
});

test('a Caddyfile or source that lost its list throws instead of passing', () => {
  assert.throws(() => caddyRanges('{\n}\n'));
  assert.throws(() => codeRanges('export const OTHER = [];'));
});
