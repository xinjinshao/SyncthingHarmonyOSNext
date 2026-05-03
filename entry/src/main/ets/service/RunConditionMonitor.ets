import connection from '@ohos.net.connection';
import { Logger } from '../common/Logger';
import { EventBus, SyncthingEvents } from '../common/EventBus';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from './Constants';
import { RunCondition } from '../types/index';

const TAG = 'RunConditionMonitor';

export enum RunDecision {
  SHOULD_RUN = 'shouldRun',
  SHOULD_NOT_RUN = 'shouldNotRun',
  FORCE_START = 'forceStart',
  FORCE_STOP = 'forceStop',
}

export interface RunConditionResult {
  decision: RunDecision;
  reason: string;
}

/**
 * Evaluates user-selected sync conditions against available HarmonyOS signals.
 *
 * Network state is wired today. Battery, power, and other platform conditions
 * are represented in the UI but remain guarded until the corresponding Harmony
 * APIs are connected.
 */
export class RunConditionMonitor {
  private preferencesManager: PreferencesManager;
  private currentConditions: RunCondition | null = null;
  private isMonitoring: boolean = false;
  private monitorTimer: number | null = null;
  private readonly MONITOR_INTERVAL_MS: number = 30000;

  constructor(preferencesManager: PreferencesManager) {
    this.preferencesManager = preferencesManager;
  }

  async startMonitoring(): Promise<void> {
    if (this.isMonitoring) {
      return;
    }
    this.isMonitoring = true;
    Logger.i(TAG, 'RunConditionMonitor started');
    await this.scheduleCheck();
  }

  stopMonitoring(): void {
    this.isMonitoring = false;
    if (this.monitorTimer !== null) {
      clearTimeout(this.monitorTimer);
      this.monitorTimer = null;
    }
    Logger.i(TAG, 'RunConditionMonitor stopped');
  }

  private async scheduleCheck(): Promise<void> {
    if (!this.isMonitoring) {
      return;
    }
    await this.checkConditions();
    this.monitorTimer = setTimeout(() => {
      this.scheduleCheck();
    }, this.MONITOR_INTERVAL_MS);
  }

  async checkConditions(): Promise<RunConditionResult> {
    try {
      this.currentConditions = await this.preferencesManager.getRunConditions();

      const forceState = await this.preferencesManager.getNumber(
        Constants.PREF_BTNSTATE_FORCE_START_STOP,
        Constants.BTNSTATE_NO_FORCE_START_STOP
      );

      if (forceState === Constants.BTNSTATE_FORCE_START) {
        return {
          decision: RunDecision.FORCE_START,
          reason: 'Force start requested by user'
        };
      }

      if (forceState === Constants.BTNSTATE_FORCE_STOP) {
        return {
          decision: RunDecision.FORCE_STOP,
          reason: 'Force stop requested by user'
        };
      }

      if (!this.currentConditions.alwaysRunInBackground) {
        return {
          decision: RunDecision.SHOULD_NOT_RUN,
          reason: 'Background sync is disabled'
        };
      }

      const shouldRun = await this.evaluateRunConditions();
      if (shouldRun) {
        EventBus.emit(SyncthingEvents.RUN_CONDITIONS_MET, null);
        return {
          decision: RunDecision.SHOULD_RUN,
          reason: 'All run conditions are met'
        };
      } else {
        EventBus.emit(SyncthingEvents.RUN_CONDITIONS_NOT_MET, null);
        return {
          decision: RunDecision.SHOULD_NOT_RUN,
          reason: 'One or more run conditions are not met'
        };
      }
    } catch (err) {
      Logger.e(TAG, `Error checking run conditions: ${JSON.stringify(err)}`);
      return {
        decision: RunDecision.SHOULD_NOT_RUN,
        reason: `Error: ${JSON.stringify(err)}`
      };
    }
  }

  private async evaluateRunConditions(): Promise<boolean> {
    if (!this.currentConditions) {
      return false;
    }

    const networkAllowed = await this.evaluateNetworkConditions(this.currentConditions);
    if (!networkAllowed) {
      return false;
    }

    if (this.currentConditions.runOnTimeSchedule) {
      const syncDuration = this.currentConditions.syncDurationMinutes;
      const sleepInterval = this.currentConditions.sleepIntervalMinutes;
      if (syncDuration > 0 && sleepInterval > 0) {
        const now = Date.now();
        const totalCycleMs = (syncDuration + sleepInterval) * 60 * 1000;
        const cyclePosition = now % totalCycleMs;

        if (cyclePosition >= syncDuration * 60 * 1000) {
          Logger.d(TAG, 'In sleep interval, not running');
          return false;
        }
      }
    }

    return true;
  }

  private async evaluateNetworkConditions(conditions: RunCondition): Promise<boolean> {
    if (!canIUse('SystemCapability.Communication.NetManager.Core')) {
      Logger.w(TAG, 'NetManager syscap unavailable, skipping network run-condition checks');
      return true;
    }

    try {
      const defaultNet = await connection.getDefaultNet();
      const capabilities = await connection.getNetCapabilities(defaultNet);
      const bearers: Array<connection.NetBearType> = capabilities.bearerTypes;
      const caps: Array<connection.NetCap> = capabilities.networkCap === undefined ? [] : capabilities.networkCap;
      const isWifi = this.hasBearer(bearers, connection.NetBearType.BEARER_WIFI);
      const isCellular = this.hasBearer(bearers, connection.NetBearType.BEARER_CELLULAR);
      const isUnmetered = this.hasNetCap(caps, connection.NetCap.NET_CAPABILITY_NOT_METERED);

      if (isWifi && !conditions.runOnWifi) {
        Logger.i(TAG, 'Wi-Fi network is active but Wi-Fi sync is disabled');
        return false;
      }
      if (isWifi && !isUnmetered && !conditions.runOnMeteredWifi) {
        Logger.i(TAG, 'Metered Wi-Fi network is active but metered Wi-Fi sync is disabled');
        return false;
      }
      if (isCellular && !conditions.runOnMobileData) {
        Logger.i(TAG, 'Cellular network is active but mobile-data sync is disabled');
        return false;
      }
      if (!isWifi && !isCellular && !conditions.runOnMobileData && !conditions.runOnWifi) {
        Logger.i(TAG, 'Default network is neither Wi-Fi nor cellular and no network type is allowed');
        return false;
      }
      return true;
    } catch (err) {
      Logger.w(TAG, `Network run-condition check failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private hasBearer(bearers: Array<connection.NetBearType>, expected: connection.NetBearType): boolean {
    for (let i = 0; i < bearers.length; i++) {
      if (bearers[i] === expected) {
        return true;
      }
    }
    return false;
  }

  private hasNetCap(caps: Array<connection.NetCap>, expected: connection.NetCap): boolean {
    for (let i = 0; i < caps.length; i++) {
      if (caps[i] === expected) {
        return true;
      }
    }
    return false;
  }

  async getButtonState(): Promise<number> {
    return await this.preferencesManager.getNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_NO_FORCE_START_STOP
    );
  }

  async setForceStart(): Promise<void> {
    await this.preferencesManager.putNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_FORCE_START
    );
    await this.checkConditions();
  }

  async setForceStop(): Promise<void> {
    await this.preferencesManager.putNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_FORCE_STOP
    );
    await this.checkConditions();
  }

  async clearForceStartStop(): Promise<void> {
    await this.preferencesManager.putNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_NO_FORCE_START_STOP
    );
    await this.checkConditions();
  }
}
