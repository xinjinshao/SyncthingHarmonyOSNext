import fileIo from '@ohos.file.fs';
import { Logger } from '../common/Logger';
import { Utils } from '../common/Utils';

const TAG = 'SandboxViewPage';
const SANDBOX_ROOT = '/data/storage/el2/base/files';

class SandboxFileRow {
  name: string = '';
  path: string = '';
  isDirectory: boolean = false;
  size: number = 0;
  modifiedTime: number = 0;
}

@Entry
@Component
struct SandboxViewPage {
  @State currentPath: string = SANDBOX_ROOT;
  @State rows: SandboxFileRow[] = [];
  @State isLoading: boolean = true;
  @State statusText: string = '';
  @State previewTitle: string = '';
  @State previewText: string = '';

  aboutToAppear(): void {
    Logger.i(TAG, 'SandboxViewPage appearing');
    this.loadPath(SANDBOX_ROOT);
  }

  build() {
    Column() {
      this.header()

      Column({ space: 6 }) {
        Text(this.currentPath)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#777')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.statusText.length > 0) {
          Text(this.statusText)
            .fontSize(12)
            .fontColor(this.statusText.indexOf('failed') >= 0 ? '#FF3B30' : '#777')
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')

      if (this.previewText.length > 0) {
        Column({ space: 6 }) {
          Row() {
            Text(this.previewTitle)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
            Button('Close')
              .height(28)
              .fontSize(12)
              .backgroundColor('#E9EEF5')
              .fontColor('#007AFF')
              .onClick(() => {
                this.previewTitle = '';
                this.previewText = '';
              })
          }
          .width('100%')
          Text(this.previewText)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor('#333')
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFFBEA')
      }

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          Text('Loading sandbox...')
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.rows.length === 0) {
        Column({ space: 12 }) {
          Text('No files in this folder')
            .fontSize(16)
            .fontColor('#888')
          Text('This view reads the app sandbox through HarmonyOS file APIs.')
            .fontSize(12)
            .fontColor('#999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.rows, (row: SandboxFileRow) => {
            ListItem() {
              this.fileItem(row)
            }
          }, (row: SandboxFileRow) => row.path)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8, bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button('<')
        .width(40)
        .height(40)
        .backgroundColor('#E9EEF5')
        .fontColor('#222')
        .onClick(() => this.getUIContext().getRouter().back())

      Text('Sandbox Files')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button('Up')
        .height(36)
        .enabled(this.currentPath !== SANDBOX_ROOT)
        .backgroundColor(this.currentPath === SANDBOX_ROOT ? '#E8E8E8' : '#E9EEF5')
        .fontColor(this.currentPath === SANDBOX_ROOT ? '#999' : '#007AFF')
        .onClick(() => this.goUp())

      Button('Refresh')
        .height(36)
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .onClick(() => this.loadPath(this.currentPath))
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  fileItem(row: SandboxFileRow) {
    Row() {
      Text(row.isDirectory ? 'DIR' : 'FILE')
        .fontSize(10)
        .fontColor(row.isDirectory ? '#007AFF' : '#34C759')
        .width(36)

      Column({ space: 4 }) {
        Text(row.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detailText(row))
          .fontSize(11)
          .fontColor('#888')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (row.isDirectory) {
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(18)
          .height(18)
          .fillColor('#CCC')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      if (row.isDirectory) {
        this.loadPath(row.path);
      } else {
        this.previewFile(row);
      }
    })
  }

  private async loadPath(path: string): Promise<void> {
    this.isLoading = true;
    this.statusText = '';
    this.previewTitle = '';
    this.previewText = '';
    try {
      const names = await fileIo.listFile(path);
      const nextRows: SandboxFileRow[] = [];
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        const childPath = this.joinPath(path, name);
        try {
          const stat = await fileIo.stat(childPath);
          const row = new SandboxFileRow();
          row.name = name;
          row.path = childPath;
          row.isDirectory = stat.isDirectory();
          row.size = stat.size;
          row.modifiedTime = stat.mtime;
          nextRows.push(row);
        } catch (err) {
          Logger.w(TAG, `Failed to stat sandbox child: ${childPath}, ${JSON.stringify(err)}`);
        }
      }
      this.rows = this.sortRows(nextRows);
      this.currentPath = path;
      this.statusText = `${this.rows.length} items`;
    } catch (err) {
      Logger.e(TAG, `Failed to list sandbox path ${path}: ${JSON.stringify(err)}`);
      this.rows = [];
      this.statusText = `List failed: ${JSON.stringify(err)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private previewFile(row: SandboxFileRow): void {
    if (row.size > 64 * 1024) {
      this.previewTitle = row.name;
      this.previewText = `File exists at ${row.path}\nSize: ${Utils.formatBytes(row.size)}\nPreview skipped for files larger than 64 KB.`;
      return;
    }
    try {
      this.previewTitle = row.name;
      this.previewText = fileIo.readTextSync(row.path);
    } catch (err) {
      this.previewTitle = row.name;
      this.previewText = `File exists at ${row.path}\nSize: ${Utils.formatBytes(row.size)}\nText preview unavailable: ${JSON.stringify(err)}`;
    }
  }

  private goUp(): void {
    if (this.currentPath === SANDBOX_ROOT) {
      return;
    }
    const index = this.currentPath.lastIndexOf('/');
    if (index <= SANDBOX_ROOT.length) {
      this.loadPath(SANDBOX_ROOT);
      return;
    }
    this.loadPath(this.currentPath.substring(0, index));
  }

  private joinPath(parent: string, name: string): string {
    if (parent.endsWith('/')) {
      return `${parent}${name}`;
    }
    return `${parent}/${name}`;
  }

  private sortRows(rows: SandboxFileRow[]): SandboxFileRow[] {
    return rows.sort((left: SandboxFileRow, right: SandboxFileRow): number => {
      if (left.isDirectory && !right.isDirectory) {
        return -1;
      }
      if (!left.isDirectory && right.isDirectory) {
        return 1;
      }
      return left.name.localeCompare(right.name);
    });
  }

  private detailText(row: SandboxFileRow): string {
    if (row.isDirectory) {
      return row.path;
    }
    return `${Utils.formatBytes(row.size)}  ${row.path}`;
  }
}
