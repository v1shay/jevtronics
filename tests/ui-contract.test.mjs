import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../web/src/main.jsx', import.meta.url), 'utf8');

test('uses every Libraries.dev visual package', () => {
  for (const packageName of ['border-beam', 'thinking-orbs', 'liquid-gooey', 'voice-glow', 'metal-fx', 'img-fx']) {
    assert.match(source, new RegExp(`from ['"]${packageName}['"]`));
  }
});

test('exposes native bridge actions for confirmation', () => {
  assert.match(source, /send\('confirm'\)/);
  assert.match(source, /send\('cancel'\)/);
  assert.match(source, /window\.notch/);
});
