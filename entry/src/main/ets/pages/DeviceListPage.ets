import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { Constants } from '../service/Constants';
import { Device } from '../model/Device';

const TAG = 'DeviceListPage';

@Component
export struct DeviceListPage {
  @State devices: Device[] = [];
  @State connectedDeviceIds: string[] = [];
  @State isLoading: boolean = true;
  @State showEmpty: boolean = false;
  @State localDeviceId: string = '';

  private restApi: RestApi | null = null;
  private refreshTimer: number | null = null;

  aboutToAppear(): void {
    Logger.i(TAG, 'DeviceListPage appearing');
    this.loadDevices(true);
    this.startTimer();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  async loadDevices(showLoading: boolean = false): Promise<void> {
    try {
      if (showLoading) {
        this.isLoading = true;
      }
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api) {
        this.restApi = api;
        await this.loadLocalDeviceId(api);
        const result = await api.getDevices();
        if (result.success && result.data) {
          this.devices = this.filterRemoteDevices(result.data);
          this.showEmpty = this.devices.length === 0;
          await this.loadConnections(api);
        }
      }
    } catch (err) {
      Logger.e(TAG, `Error loading devices: ${JSON.stringify(err)}`);
    } finally {
      if (showLoading) {
        this.isLoading = false;
      }
    }
  }

  private async loadLocalDeviceId(api: RestApi): Promise<void> {
    const result = await api.getSystemStatus();
    if (result.success && result.data !== undefined) {
      if (result.data.myID !== undefined && result.data.myID.length > 0) {
        this.localDeviceId = result.data.myID;
      } else if (result.data.myId !== undefined && result.data.myId.length > 0) {
        this.localDeviceId = result.data.myId;
      }
    }
  }

  private filterRemoteDevices(devices: Device[]): Device[] {
    const rows: Device[] = [];
    for (let i = 0; i < devices.length; i++) {
      const id = this.getDeviceId(devices[i]);
      if (id.length > 0 && id !== this.localDeviceId) {
        rows.push(devices[i]);
      }
    }
    return rows;
  }

  private async loadConnections(api: RestApi): Promise<void> {
    const result = await api.getConnections();
    if (!result.success || result.data === undefined) {
      this.connectedDeviceIds = [];
      return;
    }
    const connected: string[] = [];
    const ids = Object.keys(result.data.connections);
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      if (result.data.connections[id].connected) {
        connected.push(id);
      }
    }
    this.connectedDeviceIds = connected;
  }

  private startTimer(): void {
    this.stopTimer();
    this.refreshTimer = setInterval(() => {
      this.loadDevices(false);
    }, Constants.REST_UPDATE_INTERVAL_MS);
  }

  private stopTimer(): void {
    if (this.refreshTimer !== null) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  build() {
    Column() {
      Row() {
        Text('Devices')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Button('Add')
          .type(ButtonType.Capsule)
          .height(34)
          .backgroundColor('#007AFF')
          .fontColor(Color.White)
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/DeviceDetailPage',
              params: { mode: 'create' }
            });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          Text('Loading devices...')
            .fontSize(14)
            .fontColor('#888')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.showEmpty || this.devices.length === 0) {
        Column({ space: 16 }) {
          Text('No devices configured')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)

          Text('Add a remote device to start syncing folders')
            .fontSize(14)
            .fontColor('#888')
            .textAlign(TextAlign.Center)
            .width('80%')

          Button('Add Device')
            .type(ButtonType.Capsule)
            .backgroundColor('#007AFF')
            .fontColor(Color.White)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/DeviceDetailPage',
                params: { mode: 'create' }
              });
            })
            .margin({ top: 10 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.devices, (device: Device) => {
            ListItem() {
              this.deviceItem(device)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  deviceItem(device: Device) {
    Row() {
      Column({ space: 4 }) {
        Text(device.name || this.getDeviceId(device).substring(0, 8))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333')

        Text(this.getDeviceId(device))
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(this.getConnectionLabel(device))
            .fontSize(11)
            .fontColor(this.getConnectionColor(device))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.getConnectionBackground(device))

          Text(device.compression)
            .fontSize(11)
            .fontColor('#666')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#EEEEEE')
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(20)
        .height(20)
        .fillColor('#CCC')
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/DeviceDetailPage',
        params: { deviceId: this.getDeviceId(device) }
      });
    })
  }

  private getDeviceId(device: Device): string {
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    if (device.deviceID !== undefined) {
      return device.deviceID;
    }
    return '';
  }

  private getConnectionLabel(device: Device): string {
    if (device.paused) {
      return 'Paused';
    }
    return this.isDeviceConnected(device) ? 'Connected' : 'Waiting';
  }

  private getConnectionColor(device: Device): string {
    if (device.paused) {
      return '#FF9500';
    }
    return this.isDeviceConnected(device) ? '#34C759' : '#8E8E93';
  }

  private getConnectionBackground(device: Device): string {
    if (device.paused) {
      return '#FFF3E0';
    }
    return this.isDeviceConnected(device) ? '#E8F5E9' : '#F0F0F0';
  }

  private isDeviceConnected(device: Device): boolean {
    const id = this.getDeviceId(device);
    for (let i = 0; i < this.connectedDeviceIds.length; i++) {
      if (this.connectedDeviceIds[i] === id) {
        return true;
      }
    }
    return false;
  }
}
