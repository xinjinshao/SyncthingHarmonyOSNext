import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import { BackgroundSyncManager } from '../service/BackgroundSyncManager';
import { SyncthingService } from '../service/SyncthingService';
import { RunCondition } from '../types/index';

const TAG = 'SyncConditionsPage';

/**
 * User-facing controls for sync run conditions and continuous background sync.
 */
@Entry
@Component
struct SyncConditionsPage {
  @State isLoading: boolean = true;
  @State statusText: string = '';
  @State alwaysRunInBackground: boolean = false;
  @State runOnWifi: boolean = true;
  @State runOnMeteredWifi: boolean = true;
  @State runOnMobileData: boolean = false;
  @State runOnRoaming: boolean = false;
  @State useWifiSsidWhitelist: boolean = false;
  @State wifiSsidWhitelist: string = '';
  @State powerSource: string = Constants.POWER_SOURCE_CHARGER_BATTERY;
  @State respectBatterySaving: boolean = true;
  @State respectMasterSync: boolean = true;
  @State runInFlightMode: boolean = false;
  @State runOnTimeSchedule: boolean = false;
  @State syncDurationMinutesText: string = '0';
  @State sleepIntervalMinutesText: string = '0';

  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  aboutToAppear(): void {
    Logger.i(TAG, 'SyncConditionsPage appearing');
    this.loadConditions();
  }

  build() {
    Column() {
      this.header()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          Text('Loading sync conditions...')
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItemGroup({ header: this.sectionHeader('Background') }) {
            ListItem() {
              this.toggleItem('Background Sync', 'Keep Syncthing running with a persistent system notification', this.alwaysRunInBackground, (value: boolean) => {
                this.setBackgroundSync(value);
              })
            }
          }

          ListItemGroup({ header: this.sectionHeader('Network') }) {
            ListItem() {
              this.toggleItem('Run on Wi-Fi', 'Allow sync while the default network is Wi-Fi', this.runOnWifi, (value: boolean) => {
                this.runOnWifi = value;
                this.saveBoolean(Constants.PREF_RUN_ON_WIFI, value);
              })
            }
            ListItem() {
              this.toggleItem('Run on Metered Wi-Fi', 'Allow sync on Wi-Fi networks reported as metered', this.runOnMeteredWifi, (value: boolean) => {
                this.runOnMeteredWifi = value;
                this.saveBoolean(Constants.PREF_RUN_ON_METERED_WIFI, value);
              })
            }
            ListItem() {
              this.toggleItem('Run on Mobile Data', 'Allow sync while the default network is cellular', this.runOnMobileData, (value: boolean) => {
                this.runOnMobileData = value;
                this.saveBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, value);
              })
            }
            ListItem() {
              this.pendingToggleItem('Run while Roaming', 'Pending roaming state detection', this.runOnRoaming)
            }
            ListItem() {
              this.pendingToggleItem('Wi-Fi SSID List', 'Pending current SSID access', this.useWifiSsidWhitelist)
            }
            ListItem() {
              this.pendingTextItem('Allowed SSIDs', 'Pending current SSID access', this.wifiSsidWhitelist)
            }
          }

          ListItemGroup({ header: this.sectionHeader('Power') }) {
            ListItem() {
              this.pendingPowerSourceItem()
            }
            ListItem() {
              this.pendingToggleItem('Respect Battery Saver', 'Pending battery saver state integration', this.respectBatterySaving)
            }
            ListItem() {
              this.pendingToggleItem('Respect Master Sync', 'Pending Harmony equivalent mapping', this.respectMasterSync)
            }
            ListItem() {
              this.pendingToggleItem('Run in Flight Mode', 'Pending flight mode state integration', this.runInFlightMode)
            }
          }

          ListItemGroup({ header: this.sectionHeader('Schedule') }) {
            ListItem() {
              this.toggleItem('Timed Schedule', 'Alternate between sync and sleep windows', this.runOnTimeSchedule, (value: boolean) => {
                this.runOnTimeSchedule = value;
                this.saveBoolean(Constants.PREF_RUN_ON_TIME_SCHEDULE, value);
              })
            }
            if (this.runOnTimeSchedule) {
              ListItem() {
                this.textItem('Sync Duration Minutes', 'How long each active window lasts', this.syncDurationMinutesText, (value: string) => {
                  this.syncDurationMinutesText = this.normalizeNumber(value);
                }, () => this.saveNumber(Constants.PREF_SYNC_DURATION_MINUTES, this.parsePositiveInt(this.syncDurationMinutesText)))
              }
              ListItem() {
                this.textItem('Sleep Interval Minutes', 'How long to pause after each active window', this.sleepIntervalMinutesText, (value: string) => {
                  this.sleepIntervalMinutesText = this.normalizeNumber(value);
                }, () => this.saveNumber(Constants.PREF_SLEEP_INTERVAL_MINUTES, this.parsePositiveInt(this.sleepIntervalMinutesText)))
              }
            }
          }

          if (this.statusText.length > 0) {
            ListItem() {
              Text(this.statusText)
                .fontSize(13)
                .fontColor('#34C759')
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      Button('<')
        .width(40)
        .height(40)
        .backgroundColor('#E9EEF5')
        .fontColor('#222')
        .onClick(() => this.getUIContext().getRouter().back())
      Text('Sync Conditions')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
      Button('Reload')
        .height(36)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .onClick(() => this.loadConditions())
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#888')
      .fontWeight(FontWeight.Bold)
      .margin({ left: 8, top: 16, bottom: 4 })
      .textCase(TextCase.UpperCase)
  }

  @Builder
  toggleItem(title: string, subtitle: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor('#333')
        Text(subtitle)
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingToggleItem(title: string, subtitle: string, value: boolean) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor('#999')
          .decoration({ type: TextDecorationType.LineThrough })
        Text(subtitle)
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .enabled(false)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  textItem(title: string, subtitle: string, value: string, onChange: (value: string) => void, onSubmit: () => void) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
      Text(subtitle)
        .fontSize(12)
        .fontColor('#999')
      TextInput({ text: value })
        .height(40)
        .fontSize(14)
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
        .onChange(onChange)
        .onSubmit(() => onSubmit())
      Button('Save')
        .height(32)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .onClick(onSubmit)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingTextItem(title: string, subtitle: string, value: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(16)
        .fontColor('#999')
        .decoration({ type: TextDecorationType.LineThrough })
      Text(subtitle)
        .fontSize(12)
        .fontColor('#999')
      TextInput({ text: value })
        .height(40)
        .enabled(false)
        .fontSize(14)
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
      Button('Save')
        .height(32)
        .enabled(false)
        .backgroundColor('#E8E8E8')
        .fontColor('#999')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  powerSourceItem() {
    Column({ space: 8 }) {
      Text('Power Source')
        .fontSize(16)
        .fontColor('#333')
      Row({ space: 8 }) {
        this.powerChip(Constants.POWER_SOURCE_CHARGER_BATTERY, 'Any')
        this.powerChip(Constants.POWER_SOURCE_CHARGER, 'Charging')
        this.powerChip(Constants.POWER_SOURCE_BATTERY, 'Battery')
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingPowerSourceItem() {
    Column({ space: 8 }) {
      Text('Power Source')
        .fontSize(16)
        .fontColor('#999')
        .decoration({ type: TextDecorationType.LineThrough })
      Text('Pending charging/battery state integration')
        .fontSize(12)
        .fontColor('#999')
      Row({ space: 8 }) {
        this.pendingPowerChip('Any')
        this.pendingPowerChip('Charging')
        this.pendingPowerChip('Battery')
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingPowerChip(label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .enabled(false)
      .backgroundColor('#E8E8E8')
      .fontColor('#999')
  }

  @Builder
  powerChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.powerSource === value ? '#007AFF' : '#F5F7FA')
      .fontColor(this.powerSource === value ? Color.White : '#333')
      .onClick(() => {
        this.powerSource = value;
        this.saveString(Constants.PREF_POWER_SOURCE, value);
      })
  }

  private async loadConditions(): Promise<void> {
    this.isLoading = true;
    try {
      const conditions: RunCondition = await this.preferencesManager.getRunConditions();
      this.alwaysRunInBackground = conditions.alwaysRunInBackground;
      this.runOnWifi = conditions.runOnWifi;
      this.runOnMeteredWifi = conditions.runOnMeteredWifi;
      this.runOnMobileData = conditions.runOnMobileData;
      this.runOnRoaming = conditions.runOnRoaming;
      this.useWifiSsidWhitelist = conditions.useWifiSsidWhitelist;
      this.wifiSsidWhitelist = conditions.wifiSsidWhitelist;
      this.powerSource = conditions.powerSource;
      this.respectBatterySaving = conditions.respectBatterySaving;
      this.respectMasterSync = conditions.respectMasterSync;
      this.runInFlightMode = conditions.runInFlightMode;
      this.runOnTimeSchedule = conditions.runOnTimeSchedule;
      this.syncDurationMinutesText = conditions.syncDurationMinutes.toString();
      this.sleepIntervalMinutesText = conditions.sleepIntervalMinutes.toString();
      this.statusText = '';
    } catch (err) {
      Logger.e(TAG, `Failed to load sync conditions: ${JSON.stringify(err)}`);
      this.statusText = 'Failed to load sync conditions';
    } finally {
      this.isLoading = false;
    }
  }

  private async saveBoolean(key: string, value: boolean): Promise<void> {
    await this.preferencesManager.putBoolean(key, value);
    this.showSaved();
  }

  private async setBackgroundSync(value: boolean): Promise<void> {
    const previous = this.alwaysRunInBackground;
    this.alwaysRunInBackground = value;
    this.statusText = value ? 'Starting background sync...' : 'Stopping background sync...';

    try {
      await this.preferencesManager.putBoolean(Constants.PREF_START_SERVICE_ON_BOOT, value);
      const manager = ServiceLocator.get<BackgroundSyncManager>(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER);
      if (manager === undefined) {
        throw new Error('Background sync manager is not ready');
      }

      if (value) {
        const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
        if (service !== undefined && service.getState() !== 'active') {
          await service.startService();
        }
        const ok = await manager.enable();
        if (!ok) {
          throw new Error(manager.getLastError());
        }
        this.statusText = 'Background Sync saved. System continuous task notification is active.';
      } else {
        const ok = await manager.disable();
        if (!ok) {
          throw new Error(manager.getLastError());
        }
        this.statusText = 'Background Sync stopped. System continuous task notification removed.';
      }
    } catch (err) {
      this.alwaysRunInBackground = previous;
      await this.preferencesManager.putBoolean(Constants.PREF_START_SERVICE_ON_BOOT, previous);
      Logger.e(TAG, `Failed to change background sync: ${JSON.stringify(err)}`);
      this.statusText = `Background Sync failed: ${JSON.stringify(err)}`;
    }
  }

  private async saveString(key: string, value: string): Promise<void> {
    await this.preferencesManager.putString(key, value.trim());
    this.showSaved();
  }

  private async saveNumber(key: string, value: number): Promise<void> {
    await this.preferencesManager.putNumber(key, value);
    this.showSaved();
  }

  private showSaved(): void {
    this.statusText = 'Sync condition saved';
    this.showToast('Saved');
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }

  private normalizeNumber(value: string): string {
    const sanitized = value.trim().replace(/[^0-9]/g, '');
    return sanitized.length === 0 ? '0' : sanitized;
  }

  private parsePositiveInt(value: string): number {
    const parsed = Number.parseInt(this.normalizeNumber(value), 10);
    if (Number.isNaN(parsed) || parsed < 0) {
      return 0;
    }
    return parsed;
  }
}
