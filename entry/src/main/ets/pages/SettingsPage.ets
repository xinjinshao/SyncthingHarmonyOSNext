import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { RestApi } from '../network/RestApi';
import { Constants } from '../service/Constants';
import { Options } from '../model/Index';

const TAG = 'SettingsPage';

/**
 * Application and Syncthing settings page backed by the local REST config API.
 */
@Entry
@Component
struct SettingsPage {
  @State appTheme: string = 'system';
  @State runOnWifi: boolean = true;
  @State runOnMobileData: boolean = false;
  @State verboseLog: boolean = false;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State listenAddressesText: string = 'default';
  @State globalServersText: string = 'default';
  @State maxRecvKbpsText: string = '0';
  @State maxSendKbpsText: string = '0';
  @State natEnabled: boolean = true;
  @State localDiscovery: boolean = true;
  @State globalDiscovery: boolean = true;
  @State relaysEnabled: boolean = true;
  @State limitBandwidthInLan: boolean = false;
  @State statusText: string = '';

  private restApi: RestApi | null = null;
  private options: Options | null = null;
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  aboutToAppear(): void {
    Logger.i(TAG, 'SettingsPage appearing');
    this.loadSettings();
  }

  async loadSettings(): Promise<void> {
    Logger.d(TAG, 'Loading settings');
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.statusText = 'Syncthing service is not ready';
        return;
      }
      this.restApi = api;
      await this.loadLocalPreferences();
      const optionsResult = await api.getOptions();
      if (optionsResult.success && optionsResult.data !== undefined) {
        this.applyOptions(optionsResult.data);
      } else {
        this.statusText = optionsResult.error || 'Failed to load Syncthing options';
      }
    } catch (err) {
      Logger.e(TAG, `Failed to load settings: ${JSON.stringify(err)}`);
      this.statusText = 'Failed to load settings';
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_public_arrow_left'))
            .width(24)
            .height(24)
            .fillColor('#333')
        }
        .width(40)
        .height(40)
        .backgroundColor('#F0F0F0')
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })

        Text('Settings')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          Text('Loading settings...')
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItemGroup({ header: this.sectionHeader('Syncthing Connections') }) {
            ListItem() {
              this.textItem('Listen Addresses', 'Comma separated, usually default', this.listenAddressesText, (value: string) => {
                this.listenAddressesText = value;
              }, () => this.saveOptions())
            }

            ListItem() {
              this.textItem('Max Receive KB/s', '0 means unlimited', this.maxRecvKbpsText, (value: string) => {
                this.maxRecvKbpsText = this.normalizeNumber(value);
              }, () => this.saveOptions())
            }

            ListItem() {
              this.textItem('Max Send KB/s', '0 means unlimited', this.maxSendKbpsText, (value: string) => {
                this.maxSendKbpsText = this.normalizeNumber(value);
              }, () => this.saveOptions())
            }

            ListItem() {
              this.toggleItem('Limit Bandwidth in LAN', 'Apply rate limits to local network peers', this.limitBandwidthInLan, (value) => {
                this.limitBandwidthInLan = value;
                this.saveOptions();
              })
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader('Discovery and Relay') }) {
            ListItem() {
              this.toggleItem('NAT Traversal', 'Use UPnP/NAT-PMP where available', this.natEnabled, (value) => {
                this.natEnabled = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.toggleItem('Local Discovery', 'Find devices on the same network', this.localDiscovery, (value) => {
                this.localDiscovery = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.toggleItem('Global Discovery', 'Use global discovery servers', this.globalDiscovery, (value) => {
                this.globalDiscovery = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.toggleItem('Relaying', 'Allow relay connections when direct LAN/WAN fails', this.relaysEnabled, (value) => {
                this.relaysEnabled = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.textItem('Global Announce Servers', 'Comma separated, usually default', this.globalServersText, (value: string) => {
                this.globalServersText = value;
              }, () => this.saveOptions())
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader('Run Conditions') }) {
            ListItem() {
              this.navActionItem('Sync Conditions', 'Wi-Fi, mobile data, power, schedule', 'pages/SyncConditionsPage')
            }

            ListItem() {
              this.toggleItem('Run on Wi-Fi', 'Allow sync while the default network is Wi-Fi', this.runOnWifi, (value) => {
                this.runOnWifi = value;
                this.saveLocalBoolean(Constants.PREF_RUN_ON_WIFI, value, 'Run on Wi-Fi saved');
              })
            }

            ListItem() {
              this.toggleItem('Run on Mobile Data', 'Allow sync while the default network is cellular', this.runOnMobileData, (value) => {
                this.runOnMobileData = value;
                this.saveLocalBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, value, 'Run on Mobile Data saved');
              })
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader('Debug') }) {
            ListItem() {
              this.toggleItem('Verbose Logging', 'Show detailed debug logs', this.verboseLog, (value) => {
                this.verboseLog = value;
                Logger.setVerboseLog(value);
                this.saveLocalBoolean(Constants.PREF_VERBOSE_LOG, value, 'Verbose Logging saved');
              })
            }
          }
          .width('100%')

          if (this.statusText.length > 0) {
            ListItem() {
              Text(this.statusText)
                .fontSize(13)
                .fontColor(this.statusText.indexOf('saved') >= 0 ? '#34C759' : '#777')
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }
          }

          ListItemGroup({ header: this.sectionHeader('About') }) {
            ListItem() {
              this.infoItem('App Version', '1.0.0')
            }

            ListItem() {
              this.infoItem('Syncthing Core', 'v1.31.0')
            }
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
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
        .enabled(!this.isSaving)
        .onChange((isOn: boolean) => {
          onChange(isOn);
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
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
    .borderRadius(12)
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
        .enabled(!this.isSaving)
        .fontSize(14)
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
        .onChange(onChange)
        .onSubmit(() => onSubmit())
      Button(this.isSaving ? 'Saving' : 'Save')
        .height(32)
        .enabled(!this.isSaving)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .onClick(onSubmit)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  navItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
        .layoutWeight(1)

      Row({ space: 4 }) {
        Text(value)
          .fontSize(14)
          .fontColor('#999')
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  navActionItem(title: string, value: string, url: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor('#999')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url });
    })
  }

  @Builder
  infoItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor('#999')
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  private applyOptions(options: Options): void {
    this.options = options;
    this.listenAddressesText = this.joinValues(options.listenAddresses);
    this.globalServersText = this.joinValues(options.globalAnnounceServers);
    this.maxRecvKbpsText = options.maxRecvKbps.toString();
    this.maxSendKbpsText = options.maxSendKbps.toString();
    this.natEnabled = options.natEnabled;
    this.localDiscovery = options.localAnnounceEnabled;
    this.globalDiscovery = options.globalAnnounceEnabled;
    this.relaysEnabled = options.relaysEnabled;
    this.limitBandwidthInLan = options.limitBandwidthInLan;
  }

  private async loadLocalPreferences(): Promise<void> {
    this.runOnWifi = await this.preferencesManager.getBoolean(Constants.PREF_RUN_ON_WIFI, true);
    this.runOnMobileData = await this.preferencesManager.getBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, false);
    this.verboseLog = await this.preferencesManager.getBoolean(Constants.PREF_VERBOSE_LOG, false);
  }

  private async saveLocalBoolean(key: string, value: boolean, message: string): Promise<void> {
    await this.preferencesManager.putBoolean(key, value);
    this.statusText = message;
  }

  private async saveOptions(): Promise<void> {
    if (this.restApi === null || this.options === null) {
      this.statusText = 'Syncthing service is not ready';
      return;
    }
    this.isSaving = true;
    try {
      const next = this.options;
      next.listenAddresses = this.splitValues(this.listenAddressesText, 'default');
      next.globalAnnounceServers = this.splitValues(this.globalServersText, 'default');
      next.maxRecvKbps = this.parsePositiveInt(this.maxRecvKbpsText);
      next.maxSendKbps = this.parsePositiveInt(this.maxSendKbpsText);
      next.natEnabled = this.natEnabled;
      next.localAnnounceEnabled = this.localDiscovery;
      next.globalAnnounceEnabled = this.globalDiscovery;
      next.relaysEnabled = this.relaysEnabled;
      next.limitBandwidthInLan = this.limitBandwidthInLan;

      const result = await this.restApi.putOptions(next);
      if (!result.success) {
        this.statusText = result.error || 'Failed to save Syncthing options';
        this.showToast(this.statusText);
        return;
      }
      const verify = await this.restApi.getOptions();
      if (verify.success && verify.data !== undefined) {
        this.applyOptions(verify.data);
        this.statusText = 'Syncthing options saved';
        this.showToast('Settings saved');
      } else {
        this.statusText = 'Options saved, verification failed';
      }
    } catch (err) {
      Logger.e(TAG, `Failed to save options: ${JSON.stringify(err)}`);
      this.statusText = 'Failed to save Syncthing options';
      this.showToast(this.statusText);
    } finally {
      this.isSaving = false;
    }
  }

  private joinValues(values: string[]): string {
    if (values.length === 0) {
      return 'default';
    }
    return values.join(', ');
  }

  private splitValues(value: string, fallback: string): string[] {
    const pieces = value.split(',');
    const result: string[] = [];
    for (let i = 0; i < pieces.length; i++) {
      const item = pieces[i].trim();
      if (item.length > 0) {
        result.push(item);
      }
    }
    if (result.length === 0) {
      result.push(fallback);
    }
    return result;
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }
}
