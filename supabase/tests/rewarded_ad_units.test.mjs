import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rewardedAdUnits } from '../functions/_shared/rewarded_ad_units.ts';

test('default allowlist supports both production reward formats on both platforms', () => {
  assert.deepEqual(rewardedAdUnits(), [
    'ca-app-pub-3681310687796023/8590975808',
    'ca-app-pub-3681310687796023/8331032066',
    'ca-app-pub-3681310687796023/2102597268',
    'ca-app-pub-3681310687796023/1181317704',
  ]);
  assert.equal(rewardedAdUnits().some(unit => unit.includes('3940256099942544')), false);
});
test('explicit allowlist replaces defaults, preserving fail-closed configuration', () => {
  assert.deepEqual(rewardedAdUnits(' custom-unit, another-unit , '), ['custom-unit', 'another-unit']);
  assert.deepEqual(rewardedAdUnits(''), []);
});
