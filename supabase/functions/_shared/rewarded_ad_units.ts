// Public production AdMob identifiers; both prepare and SSV must agree.
export const productionRewardedAdUnits = [
  'ca-app-pub-3681310687796023/8590975808', // Android rewarded
  'ca-app-pub-3681310687796023/8331032066', // iOS rewarded
  'ca-app-pub-3681310687796023/2102597268', // Android rewarded interstitial
  'ca-app-pub-3681310687796023/1181317704', // iOS rewarded interstitial
];

export function rewardedAdUnits(override?: string): string[] {
  return (override ?? productionRewardedAdUnits.join(','))
    .split(',').map(unit => unit.trim()).filter(Boolean);
}
