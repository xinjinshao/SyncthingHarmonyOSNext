import { webview } from '@kit.ArkWeb';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { Constants } from '../service/Constants';
import { SyncthingService } from '../service/SyncthingService';

const TAG = 'WebGuiPage';

@Entry
@Component
struct WebGuiPage {
  controller: WebviewController = new webview.WebviewController();
  @State isLoading: boolean = true;
  @State statusText: string = 'Loading Syncthing Web GUI...';
  @State currentUrl: string = Constants.SYNCTHING_BASE_URL;

  aboutToAppear(): void {
    Logger.i(TAG, 'WebGuiPage appearing');
    this.ensureServiceRunning();
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
        .onClick(() => this.getUIContext().getRouter().back())

        Text('Syncthing Web GUI')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)

        Button('Back')
          .height(36)
          .backgroundColor('#E9EEF5')
          .fontColor('#333')
          .onClick(() => this.goWebBack())

        Button('Forward')
          .height(36)
          .backgroundColor('#E9EEF5')
          .fontColor('#333')
          .onClick(() => this.goWebForward())

        Button('Reload')
          .height(36)
          .backgroundColor('#E9EEF5')
          .fontColor('#007AFF')
          .onClick(() => this.reloadWebGui())
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      if (this.isLoading || this.statusText.length > 0) {
        Row({ space: 8 }) {
          if (this.isLoading) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color('#007AFF')
          }
          Text(this.statusText)
            .fontSize(12)
            .fontColor(this.statusText.indexOf('failed') >= 0 || this.statusText.indexOf('error') >= 0 ? '#FF3B30' : '#666')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#F5F7FA')
      }

      Web({ src: `${Constants.SYNCTHING_BASE_URL}`, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onErrorReceive((event) => {
          Logger.e(TAG, `WebView error: ${JSON.stringify(event)}`);
          this.isLoading = false;
          this.statusText = 'Web GUI load failed. Check whether the Syncthing service is running.';
        })
        .onPageBegin((event) => {
          Logger.d(TAG, `WebView page begin: ${event?.url}`);
          this.isLoading = true;
          this.currentUrl = event?.url === undefined ? Constants.SYNCTHING_BASE_URL : event.url;
          this.statusText = 'Loading Syncthing Web GUI...';
        })
        .onPageEnd((event) => {
          Logger.d(TAG, `WebView page end: ${event?.url}`);
          this.isLoading = false;
          this.currentUrl = event?.url === undefined ? this.currentUrl : event.url;
          this.statusText = '';
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  private async ensureServiceRunning(): Promise<void> {
    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service === undefined) {
      this.statusText = 'Syncthing service is not ready yet.';
      return;
    }
    if (service.getState() !== 'active') {
      this.statusText = 'Starting Syncthing service...';
      await service.startService();
    }
    this.statusText = 'Loading Syncthing Web GUI...';
  }

  private reloadWebGui(): void {
    try {
      this.isLoading = true;
      this.statusText = 'Loading Syncthing Web GUI...';
      this.controller.loadUrl(Constants.SYNCTHING_BASE_URL);
      this.controller.refresh();
    } catch (err) {
      Logger.e(TAG, `Failed to reload Web GUI: ${JSON.stringify(err)}`);
      this.isLoading = false;
      this.statusText = 'Web GUI reload failed.';
    }
  }

  private goWebBack(): void {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
      } else {
        this.getUIContext().getRouter().back();
      }
    } catch (err) {
      Logger.e(TAG, `Failed to go back in Web GUI: ${JSON.stringify(err)}`);
      this.getUIContext().getRouter().back();
    }
  }

  private goWebForward(): void {
    try {
      if (this.controller.accessForward()) {
        this.controller.forward();
      }
    } catch (err) {
      Logger.e(TAG, `Failed to go forward in Web GUI: ${JSON.stringify(err)}`);
    }
  }
}
