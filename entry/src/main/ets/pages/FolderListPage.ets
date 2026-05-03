import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { Folder, FolderStatus } from '../model/Index';

const TAG = 'FolderListPage';

@Entry
@Component
export struct FolderListPage {
  @State folders: Folder[] = [];
  @State folderStatuses: Map<string, FolderStatus> = new Map();
  @State isLoading: boolean = true;
  @State showEmpty: boolean = false;

  private restApi: RestApi | null = null;

  aboutToAppear(): void {
    Logger.i(TAG, 'FolderListPage appearing');
    this.loadFolders();
  }

  async loadFolders(): Promise<void> {
    try {
      this.isLoading = true;
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api) {
        this.restApi = api;
        const result = await api.getFolders();
        if (result.success && result.data) {
          this.folders = result.data;
          this.showEmpty = this.folders.length === 0;
          await this.loadFolderStatuses(api, this.folders);
        }
      }
    } catch (err) {
      Logger.e(TAG, `Error loading folders: ${JSON.stringify(err)}`);
    } finally {
      this.isLoading = false;
    }
  }

  private async loadFolderStatuses(api: RestApi, folders: Folder[]): Promise<void> {
    const statuses: Map<string, FolderStatus> = new Map();
    for (let i = 0; i < folders.length; i++) {
      const folder = folders[i];
      const statusResult = await api.getFolderStatus(folder.id);
      if (statusResult.success && statusResult.data !== undefined) {
        statuses.set(folder.id, statusResult.data);
      }
    }
    this.folderStatuses = statuses;
  }

  getCompletionText(folder: Folder): string {
    const status = this.folderStatuses.get(folder.id);
    if (status) {
      if (status.state.length > 0 && status.state !== 'idle') {
        return status.state;
      }
      if (status.globalBytes === 0) {
        return 'Empty';
      }
      const completed = status.globalBytes - status.needBytes;
      const percent = status.globalBytes > 0
        ? Math.round((completed / status.globalBytes) * 100)
        : 0;
      return `${percent}% synced`;
    }
    return folder.type;
  }

  getStatusColor(folder: Folder): string {
    const status = this.folderStatuses.get(folder.id);
    if (status) {
      const percent = status.globalBytes > 0
        ? Math.round(((status.globalBytes - status.needBytes) / status.globalBytes) * 100)
        : 100;
      if (status.errors > 0 || status.pullErrors > 0 || status.invalid.length > 0 || status.watchError.length > 0) {
        return '#FF3B30';
      }
      if (percent >= 100) {
        return '#34C759';
      }
      if (percent >= 50) {
        return '#007AFF';
      }
      return '#FF9500';
    }
    return '#999';
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
          Text('Loading folders...')
            .fontSize(14)
            .fontColor('#888')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.showEmpty || this.folders.length === 0) {
        Column({ space: 16 }) {
          Text('No folders configured')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)

          Text('Add a folder to start syncing files')
            .fontSize(14)
            .fontColor('#888')
            .textAlign(TextAlign.Center)
            .width('80%')

          Button('Add Folder')
            .type(ButtonType.Capsule)
            .backgroundColor('#007AFF')
            .fontColor(Color.White)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/FolderDetailPage' });
            })
            .margin({ top: 10 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.folders, (folder: Folder) => {
            ListItem() {
              this.folderItem(folder)
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
  header() {
    Row() {
      Text('Folders')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button('View')
        .height(36)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .margin({ right: 8 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/SandboxViewPage' });
        })

      Button('Add')
        .height(36)
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/FolderDetailPage' });
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  folderItem(folder: Folder) {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(folder.label || folder.id)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333')
        }

        Text(folder.path)
          .fontSize(12)
          .fontColor('#999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(this.getCompletionText(folder))
            .fontSize(11)
            .fontColor('#FFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.getStatusColor(folder))

          Text(this.getFolderTypeLabel(folder.type))
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
        url: 'pages/FolderDetailPage',
        params: { folderId: folder.id }
      });
    })
  }

  getFolderTypeLabel(type: string): string {
    switch (type) {
      case 'sendreceive': return 'Send & Receive';
      case 'sendonly': return 'Send Only';
      case 'receiveonly': return 'Receive Only';
      case 'receiveencrypted': return 'Receive Encrypted';
      default: return type;
    }
  }
}
