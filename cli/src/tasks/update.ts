import { Config } from '../config';
import { updateAndroid } from '../android/update';
import { updateIOS, updateIOSChecks } from '../ios/update';
import { CheckFunction, check, checkPackage, logFatal } from '../common';
import { exit } from 'shelljs';


export async function updateCommand(config: Config, selectedPlatformName: string) {
  const platforms = config.selectPlatforms(selectedPlatformName);

  try {
    await check(
      config,
      [checkPackage, ...updateChecks(config, platforms)]
    );
    await Promise.all(platforms.map(platformName => {
      return update(config, platformName, true);
    }));
    exit(0);
  } catch (e) {
    logFatal(e);
  }
}

export function updateChecks(config: Config, platforms: string[]): CheckFunction[] {
  const checks: CheckFunction[] = [];
  for (let platformName of platforms) {
    if (platformName === config.ios.name) {
      checks.push(...updateIOSChecks);
    } else if (platformName === config.android.name) {
      return [];
    } else {
      throw `Platform ${platformName} is not valid.`;
    }
  }
  return checks;
}

export async function update(config: Config, platformName: string, needsUpdate: boolean) {
  if (platformName === config.ios.name) {
    await updateIOS(config, needsUpdate);
  } else if (platformName === config.android.name) {
    await updateAndroid(config, needsUpdate);
  }
}