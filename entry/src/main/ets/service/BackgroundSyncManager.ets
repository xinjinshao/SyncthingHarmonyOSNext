import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { Logger } from '../common/Logger';
import { BackgroundDiagnostics } from './BackgroundDiagnostics';

const TAG = 'BackgroundSyncManager';

/**
 * Wraps HarmonyOS continuous background tasks for Syncthing's long-running sync.
 *
 * The manager intentionally uses only the system-provided bgmode notification.
 * It also keeps a lightweight heartbeat and system-task reconciliation log so
 * background task cancellation can be diagnosed from hilog.
 */
export class BackgroundSyncManager {
  private readonly bgModes: string[] = ['dataTransfer', 'multiDeviceConnection'];
  private continuousTaskId: number = -1;
  private continuousNotificationId: number = -1;
  private enabled: boolean = false;
  private desired: boolean = false;
  private lastError: string = '';
  private context: common.UIAbilityContext | null = null;
  private heartbeatTimer: number = -1;
  private callbacksRegistered: boolean = false;
  private reenableInProgress: boolean = false;
  private readonly heartbeatIntervalMs: number = 30000;

  /**
   * Stores the UIAbility context required by BackgroundTasksKit and callbacks.
   */
  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    this.registerContinuousTaskCallbacks();
  }

  /**
   * Requests a continuous task and records the returned task/notification IDs.
   */
  async enable(): Promise<boolean> {
    this.desired = true;
    if (this.enabled) {
      this.startHeartbeat();
      await this.logSystemTaskSnapshot('enable-already-enabled');
      return true;
    }

    try {
      const uiContext = this.requireContext();
      BackgroundDiagnostics.record('background.enable.request', `modes=${this.bgModes.join(',')}`);
      await this.ensureNotificationEnabled(uiContext);
      const agent = await this.createWantAgent();
      const result = await backgroundTaskManager.startBackgroundRunning(uiContext, this.bgModes, agent);
      this.enabled = true;
      this.lastError = '';
      this.continuousNotificationId = result.notificationId;
      this.continuousTaskId = result.continuousTaskId === undefined ? -1 : result.continuousTaskId;

      Logger.i(TAG, `Background sync enabled notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
      BackgroundDiagnostics.record('background.enable.success', `notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
      await this.logSystemTaskSnapshot('enable-success');
      this.startHeartbeat();
      return true;
    } catch (err) {
      this.enabled = false;
      this.lastError = JSON.stringify(err);
      Logger.e(TAG, `Failed to enable background sync: ${this.lastError}`);
      BackgroundDiagnostics.record('background.enable.failed', this.lastError);
      return false;
    }
  }

  async disable(): Promise<boolean> {
    try {
      this.desired = false;
      const uiContext = this.requireContext();
      BackgroundDiagnostics.record('background.disable.request', `notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
      this.stopHeartbeat();
      if (this.continuousTaskId > 0) {
        await backgroundTaskManager.stopBackgroundRunning(uiContext, this.continuousTaskId);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(uiContext);
      }
      this.enabled = false;
      this.continuousTaskId = -1;
      this.continuousNotificationId = -1;
      this.lastError = '';
      Logger.i(TAG, 'Background sync disabled');
      BackgroundDiagnostics.record('background.disable.success');
      return true;
    } catch (err) {
      this.lastError = JSON.stringify(err);
      Logger.e(TAG, `Failed to disable background sync: ${this.lastError}`);
      BackgroundDiagnostics.record('background.disable.failed', this.lastError);
      return false;
    }
  }

  async refreshNotification(): Promise<void> {
    await this.ensureRunning('refreshNotification');
  }

  async ensureRunning(source: string): Promise<boolean> {
    if (!this.desired) {
      BackgroundDiagnostics.record('background.ensure.skip', `source=${source}, desired=false, enabled=${this.enabled}`);
      return false;
    }

    const snapshot = await this.logSystemTaskSnapshot(`ensure-${source}`);
    if (this.enabled && this.continuousTaskId > 0 && snapshot.indexOf(`continuousTaskId=${this.continuousTaskId}`) >= 0) {
      await this.refreshSystemContinuousTask(source);
      return true;
    }

    BackgroundDiagnostics.record('background.ensure.restart', `source=${source}, previousTaskId=${this.continuousTaskId}, snapshot=${snapshot}`);
    this.enabled = false;
    return await this.reenable(source);
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  getLastError(): string {
    return this.lastError;
  }

  getContinuousTaskId(): number {
    return this.continuousTaskId;
  }

  getNotificationId(): number {
    return this.continuousNotificationId;
  }

  private requireContext(): common.UIAbilityContext {
    if (this.context === null) {
      throw new Error('UIAbilityContext is not available for background sync');
    }
    return this.context;
  }

  private async ensureNotificationEnabled(context: common.UIAbilityContext): Promise<void> {
    const enabled = await notificationManager.isNotificationEnabled();
    BackgroundDiagnostics.record('background.notification.permission', `enabled=${enabled}`);
    if (!enabled) {
      await notificationManager.requestEnableNotification(context);
      BackgroundDiagnostics.record('background.notification.permission.requested');
    }
  }

  private async createWantAgent(): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: 'com.syncthing.syncthingharmonyosnext',
          abilityName: 'EntryAbility'
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1001,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(info);
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer >= 0) {
      return;
    }
    this.heartbeatTimer = setInterval(() => {
      this.runHeartbeat().catch((err: Error) => {
        BackgroundDiagnostics.record('background.heartbeat.failed', JSON.stringify(err));
      });
    }, this.heartbeatIntervalMs);
    BackgroundDiagnostics.record('background.heartbeat.started', `intervalMs=${this.heartbeatIntervalMs}`);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer < 0) {
      return;
    }
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = -1;
    BackgroundDiagnostics.record('background.heartbeat.stopped');
  }

  private async runHeartbeat(): Promise<void> {
    await this.ensureRunning('heartbeat');
  }

  private async refreshSystemContinuousTask(source: string): Promise<void> {
    try {
      const result = await backgroundTaskManager.updateBackgroundRunning(this.requireContext(), this.bgModes);
      if (result.notificationId > 0) {
        this.continuousNotificationId = result.notificationId;
      }
      if (result.continuousTaskId !== undefined && result.continuousTaskId > 0) {
        this.continuousTaskId = result.continuousTaskId;
      }
      this.enabled = true;
      BackgroundDiagnostics.record('background.update.success', `source=${source}, notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
    } catch (err) {
      BackgroundDiagnostics.record('background.update.failed', `source=${source}, error=${JSON.stringify(err)}`);
    }
  }

  private async reenable(source: string): Promise<boolean> {
    if (this.reenableInProgress) {
      BackgroundDiagnostics.record('background.reenable.skip', `source=${source}, reason=inProgress`);
      return false;
    }
    this.reenableInProgress = true;
    try {
      BackgroundDiagnostics.record('background.reenable.request', `source=${source}`);
      const result = await this.enable();
      BackgroundDiagnostics.record('background.reenable.result', `source=${source}, result=${result}`);
      return result;
    } finally {
      this.reenableInProgress = false;
    }
  }

  private async logSystemTaskSnapshot(source: string): Promise<string> {
    try {
      const tasks = await backgroundTaskManager.getAllContinuousTasks(this.requireContext(), true);
      const parts: string[] = [];
      for (let i = 0; i < tasks.length; i++) {
        const task = tasks[i];
        if (task.abilityName === 'EntryAbility' && this.hasManagedMode(task.backgroundModes)) {
          if (task.notificationId > 0) {
            this.continuousNotificationId = task.notificationId;
          }
          if (task.continuousTaskId > 0) {
            this.continuousTaskId = task.continuousTaskId;
          }
          this.enabled = true;
        }
        parts.push(`ability=${task.abilityName},pid=${task.pid},notificationId=${task.notificationId},continuousTaskId=${task.continuousTaskId},suspend=${task.suspendState},modes=${task.backgroundModes.join('|')}`);
      }
      const snapshot = parts.length > 0 ? parts.join(';') : 'none';
      BackgroundDiagnostics.record('background.tasks.snapshot', `source=${source}, managerEnabled=${this.enabled}, notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}, tasks=${snapshot}`);
      return snapshot;
    } catch (err) {
      const message = JSON.stringify(err);
      BackgroundDiagnostics.record('background.tasks.snapshot.failed', `source=${source}, error=${message}`);
      return `error=${message}`;
    }
  }

  private hasManagedMode(modes: string[]): boolean {
    for (let i = 0; i < modes.length; i++) {
      if (modes[i] === 'dataTransfer' || modes[i] === 'multiDeviceConnection') {
        return true;
      }
    }
    return false;
  }

  private registerContinuousTaskCallbacks(): void {
    if (this.callbacksRegistered) {
      return;
    }
    try {
      backgroundTaskManager.on('continuousTaskCancel', (info) => {
        BackgroundDiagnostics.record('background.callback.cancel', `id=${info.id}, reason=${info.reason}`);
        if (info.id === this.continuousTaskId) {
          this.enabled = false;
          this.continuousTaskId = -1;
          this.continuousNotificationId = -1;
          if (this.desired) {
            this.startHeartbeat();
            this.reenable('continuousTaskCancel').catch((err: Error) => {
              BackgroundDiagnostics.record('background.callback.cancel.reenableFailed', JSON.stringify(err));
            });
          } else {
            this.stopHeartbeat();
          }
        }
      });
      backgroundTaskManager.on('continuousTaskSuspend', (info) => {
        BackgroundDiagnostics.record('background.callback.suspend', `continuousTaskId=${info.continuousTaskId}, suspendState=${info.suspendState}, reason=${info.suspendReason}`);
      });
      backgroundTaskManager.on('continuousTaskActive', (info) => {
        BackgroundDiagnostics.record('background.callback.active', `id=${info.id}`);
      });
      this.callbacksRegistered = true;
      BackgroundDiagnostics.record('background.callbacks.registered');
    } catch (err) {
      BackgroundDiagnostics.record('background.callbacks.failed', JSON.stringify(err));
    }
  }
}
