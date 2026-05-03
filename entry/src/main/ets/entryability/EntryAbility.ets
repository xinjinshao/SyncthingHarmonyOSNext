import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import { BackgroundSyncManager } from '../service/BackgroundSyncManager';
import { SyncthingService } from '../service/SyncthingService';
import { BackgroundDiagnostics } from '../service/BackgroundDiagnostics';

const TAG = 'EntryAbility';

/**
 * Application ability entry point.
 *
 * It registers long-lived services, loads preferences, and avoids stopping the
 * Syncthing core during normal foreground/background transitions.
 */
export default class EntryAbility extends UIAbility {
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    Logger.i(TAG, 'EntryAbility onCreate');

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      Logger.e(TAG, `Failed to set colorMode: ${JSON.stringify(err)}`);
    }

    const appContext = this.context.getApplicationContext();
    ServiceLocator.registerSingleton(SERVICE_NAMES.APPLICATION_CONTEXT, appContext);
    ServiceLocator.registerSingleton(SERVICE_NAMES.UI_ABILITY_CONTEXT, this.context);

    try {
      await this.preferencesManager.initialize(appContext);
      ServiceLocator.registerSingleton(SERVICE_NAMES.PREFERENCES_MANAGER, this.preferencesManager);

      const verboseLog = await this.preferencesManager.isVerboseLogEnabled();
      Logger.setVerboseLog(verboseLog);

    } catch (err) {
      Logger.e(TAG, `Failed to initialize preferences: ${JSON.stringify(err)}`);
    }

    Logger.i(TAG, 'EntryAbility initialized successfully');
  }

  onDestroy(): void {
    Logger.i(TAG, 'EntryAbility onDestroy');
    BackgroundDiagnostics.record('ability.onDestroy');
    this.destroySafely();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.i(TAG, 'EntryAbility onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.e(TAG, `Failed to load content: ${JSON.stringify(err)}`);
        return;
      }
      Logger.i(TAG, 'Content loaded successfully');
    });
  }

  onWindowStageDestroy(): void {
    Logger.i(TAG, 'EntryAbility onWindowStageDestroy');
    BackgroundDiagnostics.record('ability.onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.i(TAG, 'EntryAbility onForeground');
    BackgroundDiagnostics.record('ability.onForeground');
    this.keepBackgroundSessionAlive('onForeground');
  }

  onBackground(): void {
    Logger.i(TAG, 'EntryAbility onBackground');
    BackgroundDiagnostics.record('ability.onBackground');
    this.keepBackgroundSessionAlive('onBackground');
  }

  private destroySafely(): void {
    this.shouldKeepBackgroundRunning()
      .then((keepRunning: boolean) => {
        if (keepRunning) {
          Logger.i(TAG, 'Background sync is enabled; keeping service registry for continuous task');
          BackgroundDiagnostics.record('ability.destroy.keepBackground');
          this.keepBackgroundSessionAlive('onDestroy');
          return;
        }
        BackgroundDiagnostics.record('ability.destroy.stopAndClear');
        const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
        if (service !== undefined) {
          service.destroy();
        }
        ServiceLocator.clear();
      })
      .catch((err: Error) => {
        Logger.e(TAG, `Failed to evaluate destroy policy: ${JSON.stringify(err)}`);
        BackgroundDiagnostics.record('ability.destroy.policyFailed', JSON.stringify(err));
        ServiceLocator.clear();
      });
  }

  private async shouldKeepBackgroundRunning(): Promise<boolean> {
    return await this.preferencesManager.getBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false);
  }

  private keepBackgroundSessionAlive(source: string): void {
    this.ensureBackgroundSession(source).catch((err: Error) => {
      Logger.e(TAG, `Failed to keep background session alive from ${source}: ${JSON.stringify(err)}`);
    });
  }

  private async ensureBackgroundSession(source: string): Promise<void> {
    const enabled = await this.shouldKeepBackgroundRunning();
    if (!enabled) {
      return;
    }

    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service !== undefined && service.getState() !== 'active') {
      Logger.i(TAG, `Restarting SyncthingService for background sync from ${source}`);
      BackgroundDiagnostics.record('ability.ensure.restartService', `source=${source}, state=${service.getState()}`);
      await service.startService();
    }

    const manager = ServiceLocator.get<BackgroundSyncManager>(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER);
    if (manager !== undefined && !manager.isEnabled()) {
      Logger.i(TAG, `Re-enabling continuous background task from ${source}`);
      BackgroundDiagnostics.record('ability.ensure.enableBackground', `source=${source}`);
      await manager.enable();
    } else if (manager !== undefined) {
      await manager.ensureRunning(source);
    }
  }
}
