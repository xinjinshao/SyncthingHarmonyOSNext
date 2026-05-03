import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import { SyncthingService } from '../service/SyncthingService';
import { SystemStatus } from '../model/Index';

const TAG = 'FirstStartPage';

@Entry
@Component
struct FirstStartPage {
  @State currentStep: number = 1;
  @State totalSteps: number = 4;
  @State generatingKey: boolean = false;
  @State deviceId: string = '';
  @State acceptTerms: boolean = false;

  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  aboutToAppear(): void {
    Logger.i(TAG, 'FirstStartPage appearing');
    this.generateDeviceId();
  }

  build() {
    Column() {
      Row() {
        Text('Welcome to Syncthing')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 40 })

      Progress({ value: this.currentStep, total: this.totalSteps, type: ProgressType.Linear })
        .width('80%')
        .height(4)
        .margin({ top: 20, bottom: 20 })

      if (this.currentStep === 1) {
        this.buildStep1()
      } else if (this.currentStep === 2) {
        this.buildStep2()
      } else if (this.currentStep === 3) {
        this.buildStep3()
      } else if (this.currentStep === 4) {
        this.buildStep4()
      }

      Blank()

      Row({ space: 16 }) {
        if (this.currentStep > 1) {
          Button('Previous')
            .onClick(() => {
              this.currentStep--;
            })
        }

        if (this.currentStep < this.totalSteps) {
          Button('Next')
            .type(ButtonType.Capsule)
            .backgroundColor('#007AFF')
            .fontColor(Color.White)
            .onClick(() => {
              this.currentStep++;
            })
        } else {
          Button('Start Syncing')
            .type(ButtonType.Capsule)
            .backgroundColor('#34C759')
            .fontColor(Color.White)
            .onClick(() => {
              this.finishFirstStart();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  buildStep1() {
    Column({ space: 20 }) {
      Text('Syncthing replaces proprietary sync and cloud services with something open, trustworthy and decentralized.')
        .fontSize(16)
        .textAlign(TextAlign.Center)
        .width('85%')
        .padding(20)
        .borderRadius(12)
        .backgroundColor('#F8F8F8')

      Text('Your data is your data alone. You deserve to choose where it is stored.')
        .fontSize(14)
        .fontColor('#666')
        .textAlign(TextAlign.Center)
        .width('85%')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildStep2() {
    Column({ space: 20 }) {
      Text('Privacy & Data Handling')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Image($r('app.media.startIcon')).width(20).height(20)
          Text('All data is encrypted in transit using TLS')
            .fontSize(14)
        }

        Row({ space: 8 }) {
          Image($r('app.media.startIcon')).width(20).height(20)
          Text('Your files never leave your devices unless you want them to')
            .fontSize(14)
        }

        Row({ space: 8 }) {
          Image($r('app.media.startIcon')).width(20).height(20)
          Text('No registration, no cloud service, no tracking')
            .fontSize(14)
        }
      }
      .width('85%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor('#F0F8FF')

      Row({ space: 8 }) {
        Checkbox()
          .select(this.acceptTerms)
          .onChange((value: boolean) => {
            this.acceptTerms = value;
          })
        Text('I understand and agree to the privacy policy')
          .fontSize(14)
      }
      .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildStep3() {
    Column({ space: 20 }) {
      Text('Device Identity')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Text('Each device gets a unique identity. This ID is used to identify your device to others.')
        .fontSize(14)
        .fontColor('#666')
        .textAlign(TextAlign.Center)
        .width('85%')

      if (this.generatingKey) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#007AFF')
      } else if (this.deviceId.length > 0) {
        Column({ space: 8 }) {
          Text('Your Device ID:')
            .fontSize(14)
            .fontColor('#888')

          Text(this.deviceId)
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor('#333')
            .width('85%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor('#F0F0F0')
            .textAlign(TextAlign.Center)
        }
      }

      Button('Generate Device Identity')
        .onClick(() => {
          this.generateDeviceId();
        })
        .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildStep4() {
    Column({ space: 20 }) {
      Text('You are ready!')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#34C759')

      Text('Syncthing is configured and ready to sync your files. Add remote devices and folders to get started.')
        .fontSize(14)
        .fontColor('#666')
        .textAlign(TextAlign.Center)
        .width('85%')

      Column({ space: 12 }) {
        Text('Next steps:')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)

        Text('1. Add folders you want to sync')
          .fontSize(14)
        Text('2. Add remote device IDs')
          .fontSize(14)
        Text('3. Share folders with devices')
          .fontSize(14)
      }
      .width('85%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor('#F8F8F8')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  async generateDeviceId(): Promise<void> {
    if (this.generatingKey || this.deviceId.length > 0) {
      return;
    }
    Logger.i(TAG, 'Generating device identity from Syncthing core');
    this.generatingKey = true;

    try {
      const service = await this.ensureSyncthingService();
      if (service.getState() !== 'active') {
        await service.startService();
      }

      const statusResult = await service.getRestApi().getSystemStatus();
      const coreDeviceId = statusResult.data !== undefined ? this.getSystemDeviceId(statusResult.data) : '';
      if (!statusResult.success || coreDeviceId.length === 0) {
        throw new Error(statusResult.error || 'Syncthing did not return a device ID');
      }

      this.deviceId = coreDeviceId;
      await this.preferencesManager.setLocalDeviceId(this.deviceId);
      Logger.i(TAG, `Device ID loaded from core: ${this.deviceId}`);
    } catch (err) {
      Logger.e(TAG, `Failed to generate device ID: ${JSON.stringify(err)}`);
    } finally {
      this.generatingKey = false;
    }
  }

  async finishFirstStart(): Promise<void> {
    Logger.i(TAG, 'Finishing first start setup');
    try {
      const service = await this.ensureSyncthingService();
      if (service.getState() !== 'active') {
        await service.startService();
      }
      if (this.deviceId.length === 0) {
        const statusResult = await service.getRestApi().getSystemStatus();
        if (statusResult.success && statusResult.data !== undefined) {
          this.deviceId = this.getSystemDeviceId(statusResult.data);
          await this.preferencesManager.setLocalDeviceId(this.deviceId);
        }
      }
      await this.preferencesManager.putBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false);
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/MainPage' });
    } catch (err) {
      Logger.e(TAG, `Error finishing first start: ${JSON.stringify(err)}`);
    }
  }

  private async ensureSyncthingService(): Promise<SyncthingService> {
    const existing = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (existing !== undefined) {
      return existing;
    }

    const service = new SyncthingService();
    await service.initialize();
    ServiceLocator.registerSingleton(SERVICE_NAMES.SYNCTHING_SERVICE, service);
    return service;
  }

  private getSystemDeviceId(status: SystemStatus): string {
    if (status.myID !== undefined && status.myID.length > 0) {
      return status.myID;
    }
    if (status.myId !== undefined && status.myId.length > 0) {
      return status.myId;
    }
    return '';
  }
}
