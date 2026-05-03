import { picker } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { RestApi } from '../network/RestApi';
import { FolderLocationManager, FolderLocationMapping } from '../service/FolderLocationManager';
import { FolderMirrorResult, FolderMirrorService } from '../service/FolderMirrorService';
import { Device, Folder, FolderDevice, FolderStatus, Versioning } from '../model/Index';

const TAG = 'FolderDetailPage';

class DeviceShareState {
  deviceId: string = '';
  name: string = '';
  shared: boolean = false;
  encryptionPassword: string = '';
}

/**
 * Folder create/edit screen that maps Harmony storage choices to Syncthing
 * folder configuration and sandbox mirror paths.
 */
@Entry
@Component
struct FolderDetailPage {
  @State isCreateMode: boolean = true;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State isScanning: boolean = false;
  @State isMirroring: boolean = false;
  @State isDeleting: boolean = false;
  @State folderId: string = '';
  @State label: string = '';
  @State path: string = '';
  @State folderType: string = 'sendreceive';
  @State pullOrder: string = 'random';
  @State versioningType: string = 'none';
  @State versionKeep: string = '5';
  @State versionCleanoutDays: string = '0';
  @State versionMaxAgeDays: string = '0';
  @State versionCommand: string = '';
  @State paused: boolean = false;
  @State ignorePerms: boolean = false;
  @State fsWatcherEnabled: boolean = true;
  @State rescanIntervalS: number = 3600;
  @State deviceShares: DeviceShareState[] = [];
  @State statusText: string = '';
  @State folderStateText: string = '';
  @State folderStatsText: string = '';
  @State pathHintText: string = '';
  @State externalFolderUri: string = '';
  @State folderSelectionSupported: boolean = false;

  private restApi: RestApi | null = null;
  private folderLocationManager: FolderLocationManager = new FolderLocationManager(PreferencesManager.getInstance());
  private folderMirrorService: FolderMirrorService = new FolderMirrorService();
  private currentFolder: Folder | null = null;
  private devices: Device[] = [];
  private pendingDeviceId: string = '';
  private localDeviceId: string = '';
  private deleteArmed: boolean = false;

  aboutToAppear(): void {
    Logger.i(TAG, 'FolderDetailPage appearing');
    this.folderSelectionSupported = canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
    this.loadFolder();
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
          Text('Loading folder...')
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            this.textField('Folder ID', this.folderId, 'folder-id', (value: string) => {
              if (this.isCreateMode) {
                this.folderId = this.normalizeFolderId(value);
              }
            }, !this.isCreateMode)

            this.textField('Label', this.label, 'Display name', (value: string) => {
              this.label = value;
            })

            this.textField('Path', this.path, '/data/storage/el2/base/files/Sync', (value: string) => {
              this.path = value.trim();
              this.externalFolderUri = '';
              this.updatePathHint();
            })
            this.pathActionsSection()

            this.syncScenarioSection()
            this.folderTypeSection()
            this.pullOrderSection()
            this.versioningSection()
            this.deviceShareSection()
            if (!this.isCreateMode) {
              this.statusSection()
              this.actionsSection()
            }

            this.switchRow('Watch for Changes', this.fsWatcherEnabled, (value: boolean) => {
              this.fsWatcherEnabled = value;
            })
            this.switchRow('Ignore Permissions', this.ignorePerms, (value: boolean) => {
              this.ignorePerms = value;
            })
            this.switchRow('Pause Folder', this.paused, (value: boolean) => {
              this.paused = value;
            })

            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(13)
                .fontColor(this.statusText.indexOf('saved') >= 0 ? '#34C759' : '#777')
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 24 })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  pathActionsSection() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('App Storage')
          .height(36)
          .layoutWeight(1)
          .backgroundColor('#007AFF')
          .fontColor(Color.White)
          .onClick(() => this.useAppStoragePath())
        Button() {
          Text('System Folder')
            .fontSize(14)
            .fontColor(this.folderSelectionSupported ? '#007AFF' : '#999')
            .decoration({ type: this.folderSelectionSupported ? TextDecorationType.None : TextDecorationType.LineThrough })
        }
        .height(36)
        .layoutWeight(1)
        .enabled(this.folderSelectionSupported)
        .backgroundColor(this.folderSelectionSupported ? '#E9EEF5' : '#E8E8E8')
        .onClick(() => this.pickFolderPath())
      }
      .width('100%')
      Row({ space: 8 }) {
        Button('Custom Path')
          .height(34)
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
          .fontColor('#333')
          .onClick(() => {
            this.externalFolderUri = '';
            if (this.path.length === 0) {
              this.path = this.folderLocationManager.getSandboxPath(this.folderId.length > 0 ? this.folderId : this.suggestFolderId());
            }
            this.updatePathHint();
          })
        Button('Mirror Status')
          .height(34)
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
          .fontColor('#007AFF')
          .onClick(() => {
            this.statusText = this.externalFolderUri.length > 0
              ? 'External folder mirror is enabled. Import runs manually and periodically for send-capable folders.'
              : 'App Storage path is directly scanned by Syncthing. External picker is not required.';
          })
      }
      .width('100%')
      if (!this.folderSelectionSupported) {
        Text('System folder picker is not supported on this phone profile. App Storage is the supported location; direct custom paths remain available for debugging.')
          .fontSize(12)
          .fontColor('#777')
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      }
      if (this.pathHintText.length > 0) {
        Text(this.pathHintText)
          .fontSize(12)
          .fontColor(this.pathHintText.indexOf('URI') >= 0 ? '#FF9500' : '#777')
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      }
      if (this.externalFolderUri.length > 0) {
        Row({ space: 8 }) {
          Button(this.isMirroring ? 'Importing' : 'Import Now')
            .height(34)
            .layoutWeight(1)
            .enabled(!this.isMirroring)
            .backgroundColor('#E9EEF5')
            .fontColor('#007AFF')
            .onClick(() => this.importExternalFolder())
          Button(this.isMirroring ? 'Exporting' : 'Export Now')
            .height(34)
            .layoutWeight(1)
            .enabled(!this.isMirroring)
            .backgroundColor('#FFFFFF')
            .fontColor('#333')
            .onClick(() => this.exportExternalFolder())
        }
        .width('100%')
        Text(`Selected: ${this.externalFolderUri}`)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#777')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  syncScenarioSection() {
    Column({ space: 8 }) {
      Text('Sync Scenario')
        .fontSize(13)
        .fontColor('#666')
      Row({ space: 8 }) {
        Button('PC -> Phone')
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.folderType === 'receiveonly' ? '#007AFF' : '#FFFFFF')
          .fontColor(this.folderType === 'receiveonly' ? Color.White : '#333')
          .onClick(() => {
            this.folderType = 'receiveonly';
            this.ensureStoragePathForScenario();
          })
        Button('Phone -> PC')
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.folderType === 'sendonly' ? '#007AFF' : '#FFFFFF')
          .fontColor(this.folderType === 'sendonly' ? Color.White : '#333')
          .onClick(() => {
            this.folderType = 'sendonly';
            this.ensureStoragePathForScenario();
          })
      }
      .width('100%')
      Row({ space: 8 }) {
        Button('Two-way')
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.folderType === 'sendreceive' ? '#007AFF' : '#FFFFFF')
          .fontColor(this.folderType === 'sendreceive' ? Color.White : '#333')
          .onClick(() => {
            this.folderType = 'sendreceive';
            this.ensureStoragePathForScenario();
          })
      }
      .width('100%')
      Text(this.getScenarioHint())
        .fontSize(12)
        .fontColor('#777')
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(8)
        .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusSection() {
    Column({ space: 6 }) {
      Text('Status')
        .fontSize(13)
        .fontColor('#666')
      Row() {
        Text(this.folderStateText.length > 0 ? this.folderStateText : 'Unknown')
          .fontSize(15)
          .fontColor('#222')
          .layoutWeight(1)
        Text(this.folderStatsText)
          .fontSize(12)
          .fontColor('#777')
      }
      .width('100%')
      .padding(14)
      .borderRadius(8)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionsSection() {
    Column({ space: 8 }) {
      Text('Folder Actions')
        .fontSize(13)
        .fontColor('#666')
      Row({ space: 8 }) {
        Button(this.isScanning ? 'Scanning' : 'Rescan')
          .height(38)
          .layoutWeight(1)
          .enabled(!this.isSaving && !this.isDeleting && !this.isScanning)
          .backgroundColor('#E9EEF5')
          .fontColor('#007AFF')
          .onClick(() => this.scanFolder())
        Button(this.isDeleting ? 'Deleting' : (this.deleteArmed ? 'Confirm Delete' : 'Delete'))
          .height(38)
          .layoutWeight(1)
          .enabled(!this.isSaving && !this.isDeleting && !this.isScanning)
          .backgroundColor(this.deleteArmed ? '#FF3B30' : '#FFF1F0')
          .fontColor(this.deleteArmed ? Color.White : '#FF3B30')
          .onClick(() => this.deleteFolder())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

      Text(this.isCreateMode ? 'Add Folder' : 'Edit Folder')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button(this.isSaving ? 'Saving' : (this.isCreateMode ? 'Create' : 'Save'))
        .height(38)
        .enabled(!this.isSaving)
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .onClick(() => {
          this.saveFolder();
        })
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  textField(label: string, value: string, placeholder: string, onChange: (value: string) => void, readOnly: boolean = false) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor('#666')
      TextInput({ text: value, placeholder })
        .height(44)
        .enabled(!readOnly)
        .fontSize(15)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  folderTypeSection() {
    Column({ space: 8 }) {
      Text('Folder Type')
        .fontSize(13)
        .fontColor('#666')
      Row({ space: 8 }) {
        this.typeChip('sendreceive', 'Send & Receive')
        this.typeChip('sendonly', 'Send Only')
      }
      .width('100%')
      Row({ space: 8 }) {
        this.typeChip('receiveonly', 'Receive Only')
        this.typeChip('receiveencrypted', 'Encrypted')
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  typeChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.folderType === value ? '#007AFF' : '#FFFFFF')
      .fontColor(this.folderType === value ? Color.White : '#333')
      .onClick(() => {
        this.folderType = value;
      })
  }

  @Builder
  pullOrderSection() {
    Column({ space: 8 }) {
      Text('Pull Order')
        .fontSize(13)
        .fontColor('#666')
      Row({ space: 8 }) {
        this.pullOrderChip('random', 'Random')
        this.pullOrderChip('alphabetic', 'Alphabetic')
      }
      .width('100%')
      Row({ space: 8 }) {
        this.pullOrderChip('smallestFirst', 'Smallest')
        this.pullOrderChip('largestFirst', 'Largest')
      }
      .width('100%')
      Row({ space: 8 }) {
        this.pullOrderChip('oldestFirst', 'Oldest')
        this.pullOrderChip('newestFirst', 'Newest')
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  pullOrderChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.pullOrder === value ? '#007AFF' : '#FFFFFF')
      .fontColor(this.pullOrder === value ? Color.White : '#333')
      .onClick(() => {
        this.pullOrder = value;
      })
  }

  @Builder
  versioningSection() {
    Column({ space: 8 }) {
      Text('File Versioning')
        .fontSize(13)
        .fontColor('#666')
      Row({ space: 8 }) {
        this.versioningChip('none', 'None')
        this.versioningChip('trashcan', 'Trashcan')
      }
      .width('100%')
      Row({ space: 8 }) {
        this.versioningChip('simple', 'Simple')
        this.versioningChip('staggered', 'Staggered')
      }
      .width('100%')
      Row({ space: 8 }) {
        this.versioningChip('external', 'External')
      }
      .width('100%')

      if (this.versioningType === 'trashcan' || this.versioningType === 'simple') {
        this.textField('Cleanout Days', this.versionCleanoutDays, '0', (value: string) => {
          this.versionCleanoutDays = this.normalizeNumber(value);
        })
      }
      if (this.versioningType === 'simple') {
        this.textField('Keep Versions', this.versionKeep, '5', (value: string) => {
          this.versionKeep = this.normalizeNumber(value);
        })
      }
      if (this.versioningType === 'staggered') {
        this.textField('Max Age Days', this.versionMaxAgeDays, '0', (value: string) => {
          this.versionMaxAgeDays = this.normalizeNumber(value);
        })
      }
      if (this.versioningType === 'external') {
        this.textField('Command', this.versionCommand, 'command path', (value: string) => {
          this.versionCommand = value.trim();
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  versioningChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.versioningType === value ? '#007AFF' : '#FFFFFF')
      .fontColor(this.versioningType === value ? Color.White : '#333')
      .onClick(() => {
        this.versioningType = value;
        this.ensureVersioningDefaults(value);
      })
  }

  @Builder
  deviceShareSection() {
    Column({ space: 8 }) {
      Row() {
        Text(`Share With Devices (${this.selectedDeviceShareCount()}/${this.deviceShares.length})`)
          .fontSize(13)
          .fontColor('#666')
          .layoutWeight(1)
        if (this.deviceShares.length > 0) {
          Button('All')
            .height(28)
            .fontSize(12)
            .backgroundColor('#E9EEF5')
            .fontColor('#007AFF')
            .onClick(() => this.setAllDeviceShares(true))
          Button('None')
            .height(28)
            .fontSize(12)
            .backgroundColor('#E9EEF5')
            .fontColor('#666')
            .margin({ left: 8 })
            .onClick(() => this.setAllDeviceShares(false))
        }
      }
      .width('100%')

      if (this.deviceShares.length === 0) {
        Text('No remote devices configured')
          .fontSize(14)
          .fontColor('#777')
          .width('100%')
          .padding(14)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
      } else {
        ForEach(this.deviceShares, (share: DeviceShareState) => {
          Column({ space: 8 }) {
            Row() {
              Text(share.name.length > 0 ? share.name : share.deviceId.substring(0, 8))
                .fontSize(15)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: share.shared })
                .onChange((value: boolean) => {
                  this.updateDeviceShare(share.deviceId, value, share.encryptionPassword);
                })
            }
            .width('100%')
            Text(share.deviceId)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor('#777')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (share.shared && this.folderType === 'receiveencrypted') {
              TextInput({ text: share.encryptionPassword, placeholder: 'Encryption password' })
                .height(40)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.updateDeviceShare(share.deviceId, share.shared, value);
                })
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
        }, (share: DeviceShareState) => share.deviceId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  switchRow(title: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor('#222')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChange)
    }
    .width('100%')
    .padding(14)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  private async loadFolder(): Promise<void> {
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.showToast('Syncthing service is not ready');
        return;
      }
      this.restApi = api;

      const params = this.getUIContext().getRouter().getParams() as Record<string, string>;
      const mode = params['mode'];
      const routeFolderId = params['folderId'];
      this.pendingDeviceId = params['deviceId'] === undefined ? '' : params['deviceId'];
      this.isCreateMode = mode === 'create' || routeFolderId === undefined || routeFolderId.length === 0;

      const devicesResult = await api.getDevices();
      if (devicesResult.success && devicesResult.data !== undefined) {
        this.devices = devicesResult.data;
      }
      const statusResult = await api.getSystemStatus();
      if (statusResult.success && statusResult.data !== undefined) {
        if (statusResult.data.myID !== undefined && statusResult.data.myID.length > 0) {
          this.localDeviceId = statusResult.data.myID;
        } else if (statusResult.data.myId !== undefined && statusResult.data.myId.length > 0) {
          this.localDeviceId = statusResult.data.myId;
        }
      }

      if (this.isCreateMode) {
        const defaultResult = await api.getDefaultFolder();
        if (defaultResult.success && defaultResult.data !== undefined) {
          this.applyFolder(defaultResult.data);
        } else {
          this.applyFolder(this.createFallbackFolder());
        }
        this.folderId = routeFolderId !== undefined && routeFolderId.length > 0 ? this.normalizeFolderId(routeFolderId) : this.suggestFolderId();
        this.label = params['label'] !== undefined && params['label'].length > 0 ? params['label'] : 'Sync';
        this.path = `/data/storage/el2/base/files/${this.folderId}`;
        this.updatePathHint();
      } else {
        const folderResult = await api.getFolder(routeFolderId);
        if (folderResult.success && folderResult.data !== undefined) {
          this.applyFolder(folderResult.data);
          await this.loadFolderLocationMapping(routeFolderId);
          await this.loadFolderStatus(routeFolderId);
        } else {
          this.showToast(folderResult.error || 'Folder not found');
        }
      }
      this.buildDeviceShares();
    } catch (err) {
      Logger.e(TAG, `Failed to load folder: ${JSON.stringify(err)}`);
      this.showToast('Failed to load folder');
    } finally {
      this.isLoading = false;
    }
  }

  private async loadFolderStatus(folderId: string): Promise<void> {
    if (this.restApi === null || folderId.length === 0) {
      return;
    }
    const statusResult = await this.restApi.getFolderStatus(folderId);
    if (statusResult.success && statusResult.data !== undefined) {
      this.applyFolderStatus(statusResult.data);
    }
  }

  private async saveFolder(): Promise<void> {
    if (this.restApi === null) {
      this.showToast('Syncthing service is not ready');
      return;
    }
    if (!this.validateFolder()) {
      return;
    }

    this.isSaving = true;
    try {
      const folder = this.buildFolderPayload();
      const prepared = await this.folderLocationManager.ensureSyncthingFolder(folder.path);
      if (!prepared) {
        this.showToast('Folder storage is not ready');
        return;
      }
      const result = await this.restApi.putFolder(folder.id, folder);
      if (!result.success) {
        this.showToast(result.error || 'Failed to save folder');
        return;
      }

      const verified = await this.verifyFolderSaved(folder.id);
      if (!verified) {
        this.showToast('Folder save was not confirmed by Syncthing');
        return;
      }
      await this.saveFolderLocationMapping(folder.id, folder.path);

      this.statusText = 'Folder saved';
      this.showToast(this.isCreateMode ? 'Folder created' : 'Folder saved');
      this.getUIContext().getRouter().back();
    } catch (err) {
      Logger.e(TAG, `Failed to save folder: ${JSON.stringify(err)}`);
      this.showToast('Failed to save folder');
    } finally {
      this.isSaving = false;
    }
  }

  private async scanFolder(): Promise<void> {
    if (this.restApi === null) {
      this.showToast('Syncthing service is not ready');
      return;
    }
    this.isScanning = true;
    this.deleteArmed = false;
    try {
      const result = await this.restApi.scanFolder(this.folderId);
      if (!result.success) {
        this.showToast(result.error || 'Rescan failed');
        return;
      }
      this.statusText = 'Rescan requested';
      this.showToast('Rescan requested');
      await this.loadFolderStatus(this.folderId);
    } catch (err) {
      Logger.e(TAG, `Failed to scan folder: ${JSON.stringify(err)}`);
      this.showToast('Rescan failed');
    } finally {
      this.isScanning = false;
    }
  }

  private async deleteFolder(): Promise<void> {
    if (!this.deleteArmed) {
      this.deleteArmed = true;
      this.statusText = 'Tap Delete again to confirm';
      return;
    }
    if (this.restApi === null) {
      this.showToast('Syncthing service is not ready');
      return;
    }
    this.isDeleting = true;
    try {
      const result = await this.restApi.deleteFolder(this.folderId);
      if (!result.success) {
        this.showToast(result.error || 'Failed to delete folder');
        return;
      }
      await this.folderLocationManager.clearMapping(this.folderId);
      this.showToast('Folder deleted');
      this.getUIContext().getRouter().back();
    } catch (err) {
      Logger.e(TAG, `Failed to delete folder: ${JSON.stringify(err)}`);
      this.showToast('Failed to delete folder');
    } finally {
      this.isDeleting = false;
      this.deleteArmed = false;
    }
  }

  private applyFolder(folder: Folder): void {
    this.currentFolder = folder;
    this.folderId = folder.id;
    this.label = folder.label;
    this.path = folder.path;
    this.updatePathHint();
    this.folderType = folder.type.length > 0 ? folder.type : 'sendreceive';
    this.pullOrder = folder.order.length > 0 ? folder.order : 'random';
    this.applyVersioning(folder.versioning);
    this.paused = folder.paused === true;
    this.ignorePerms = folder.ignorePerms;
    this.fsWatcherEnabled = folder.fsWatcherEnabled;
    this.rescanIntervalS = folder.rescanIntervalS;
  }

  private async pickFolderPath(): Promise<void> {
    if (!this.folderSelectionSupported) {
      this.statusText = 'System folder picker is not supported on this device profile';
      return;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        this.showToast('Unable to select folder');
        return;
      }
      const documentPicker = new picker.DocumentViewPicker(hostContext);
      const uris = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const id = this.folderId.length > 0 ? this.folderId : this.suggestFolderId();
      if (this.folderId.length === 0) {
        this.folderId = id;
      }
      this.externalFolderUri = uris[0];
      this.path = this.folderLocationManager.getSandboxPath(id);
      this.updatePathHint();
      this.showToast('Folder selected');
    } catch (err) {
      Logger.e(TAG, `Failed to pick folder: ${JSON.stringify(err)}`);
      this.showToast('Unable to select folder');
    }
  }

  private useAppStoragePath(): void {
    const id = this.folderId.length > 0 ? this.folderId : this.suggestFolderId();
    if (this.folderId.length === 0) {
      this.folderId = id;
    }
    this.externalFolderUri = '';
    this.path = this.folderLocationManager.getSandboxPath(id);
    this.updatePathHint();
  }

  private updatePathHint(): void {
    if (this.externalFolderUri.length > 0) {
      this.pathHintText = 'External folder selected. Syncthing uses the sandbox mirror path until URI mirroring is enabled.';
    } else if (this.path.indexOf('://') >= 0) {
      this.pathHintText = 'Picker returned a URI. Use Select Folder again so the app can map it to a sandbox mirror path.';
    } else if (this.path.indexOf('/data/storage/el2/base/files') === 0) {
      this.pathHintText = 'App sandbox path, directly accessible by the embedded Syncthing core.';
    } else if (this.path.length > 0) {
      this.pathHintText = 'Custom filesystem path. Syncthing can use it only if the core has direct access.';
    } else {
      this.pathHintText = '';
    }
  }

  private ensureStoragePathForScenario(): void {
    if (this.path.length === 0) {
      this.useAppStoragePath();
    }
  }

  private getScenarioHint(): string {
    if (this.folderType === 'receiveonly') {
      return 'PC to phone: choose where received files land on the phone. App Storage works now; system folder selection depends on device support.';
    }
    if (this.folderType === 'sendonly') {
      return 'Phone to PC: use App Storage now, or choose a system folder only on devices that support folder selection.';
    }
    return 'Two-way: both sides can send changes. App Storage is the stable path; external folder mirroring is available when the system picker is supported.';
  }

  private async loadFolderLocationMapping(folderId: string): Promise<void> {
    const mapping: FolderLocationMapping = await this.folderLocationManager.getMapping(folderId);
    this.externalFolderUri = mapping.externalUri;
    if (mapping.syncthingPath.length > 0 && this.path !== mapping.syncthingPath) {
      Logger.w(TAG, `Folder path differs from stored mapping: ${folderId}`);
    }
    this.updatePathHint();
  }

  private async saveFolderLocationMapping(folderId: string, syncthingPath: string): Promise<void> {
    if (this.externalFolderUri.length > 0) {
      await this.folderLocationManager.saveExternalMapping(folderId, this.externalFolderUri, syncthingPath);
    } else {
      await this.folderLocationManager.clearMapping(folderId);
    }
  }

  private async importExternalFolder(): Promise<void> {
    const mapping = this.buildCurrentLocationMapping();
    this.isMirroring = true;
    try {
      const result: FolderMirrorResult = await this.folderMirrorService.importExternalToSandbox(mapping);
      this.statusText = result.message;
      this.showToast(result.message);
      if (result.success && this.restApi !== null && this.folderId.length > 0) {
        await this.restApi.scanFolder(this.folderId);
      }
    } finally {
      this.isMirroring = false;
    }
  }

  private async exportExternalFolder(): Promise<void> {
    const mapping = this.buildCurrentLocationMapping();
    this.isMirroring = true;
    try {
      const result: FolderMirrorResult = await this.folderMirrorService.exportSandboxToExternal(mapping);
      this.statusText = result.message;
      this.showToast(result.message);
    } finally {
      this.isMirroring = false;
    }
  }

  private buildCurrentLocationMapping(): FolderLocationMapping {
    const mapping = new FolderLocationMapping();
    mapping.folderId = this.folderId;
    mapping.externalUri = this.externalFolderUri;
    mapping.syncthingPath = this.path;
    return mapping;
  }

  private applyFolderStatus(status: FolderStatus): void {
    this.folderStateText = status.state.length > 0 ? status.state : 'idle';
    if (status.globalBytes === 0) {
      this.folderStatsText = `${status.localTotalItems} local items`;
      return;
    }
    const completed = status.globalBytes - status.needBytes;
    const percent = Math.round((completed / status.globalBytes) * 100);
    this.folderStatsText = `${percent}% synced`;
  }

  private buildDeviceShares(): void {
    const shares: DeviceShareState[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      const device = this.devices[i];
      const id = this.getDeviceId(device);
      if (id.length === 0 || id === this.getLocalDeviceId()) {
        continue;
      }
      const share = new DeviceShareState();
      share.deviceId = id;
      share.name = device.name;
      if (this.currentFolder !== null) {
        for (let j = 0; j < this.currentFolder.devices.length; j++) {
          const folderDevice = this.currentFolder.devices[j];
          if (this.getFolderDeviceId(folderDevice) === id) {
            share.shared = true;
            share.encryptionPassword = folderDevice.encryptionPassword;
            break;
          }
        }
      }
      if (this.pendingDeviceId.length > 0 && id === this.pendingDeviceId) {
        share.shared = true;
      }
      shares.push(share);
    }
    this.deviceShares = shares;
  }

  private buildFolderPayload(): Folder {
    let folder = this.currentFolder;
    if (folder === null) {
      folder = this.createFallbackFolder();
    }
    folder.id = this.folderId;
    folder.label = this.label;
    folder.path = this.path;
    folder.type = this.folderType;
    folder.order = this.pullOrder;
    folder.versioning = this.buildVersioning();
    folder.paused = this.paused;
    folder.ignorePerms = this.ignorePerms;
    folder.fsWatcherEnabled = this.fsWatcherEnabled;
    folder.rescanIntervalS = this.rescanIntervalS;

    const devices: FolderDevice[] = [];
    const localId = this.getLocalDeviceId();
    if (localId.length > 0) {
      devices.push({
        deviceId: localId,
        deviceID: localId,
        introducedBy: '',
        encryptionPassword: ''
      });
    }
    for (let i = 0; i < this.deviceShares.length; i++) {
      const share = this.deviceShares[i];
      if (share.shared) {
        devices.push({
          deviceId: share.deviceId,
          deviceID: share.deviceId,
          introducedBy: '',
          encryptionPassword: share.encryptionPassword
        });
      }
    }
    folder.devices = devices;
    return folder;
  }

  private applyVersioning(versioning: Versioning): void {
    this.versioningType = versioning.type.length > 0 ? versioning.type : 'none';
    this.versionCleanoutDays = this.getVersioningParam(versioning, 'cleanoutDays', '0');
    this.versionKeep = this.getVersioningParam(versioning, 'keep', '5');
    const maxAgeSeconds = this.parsePositiveInt(this.getVersioningParam(versioning, 'maxAge', '0'), 0);
    this.versionMaxAgeDays = Math.floor(maxAgeSeconds / 86400).toString();
    this.versionCommand = this.getVersioningParam(versioning, 'command', '');
  }

  private buildVersioning(): Versioning {
    const params: Record<string, string> = {};
    if (this.versioningType === 'trashcan') {
      params['cleanoutDays'] = this.normalizeNumber(this.versionCleanoutDays);
    } else if (this.versioningType === 'simple') {
      params['keep'] = this.normalizeNumber(this.versionKeep);
      params['cleanoutDays'] = this.normalizeNumber(this.versionCleanoutDays);
    } else if (this.versioningType === 'staggered') {
      const days = this.parsePositiveInt(this.versionMaxAgeDays, 0);
      params['maxAge'] = (days * 86400).toString();
    } else if (this.versioningType === 'external') {
      params['command'] = this.versionCommand;
    }

    return {
      type: this.versioningType === 'none' ? '' : this.versioningType,
      params,
      cleanupIntervalS: this.currentFolder !== null && this.currentFolder.versioning.cleanupIntervalS !== undefined
        ? this.currentFolder.versioning.cleanupIntervalS
        : 3600,
      fsPath: this.currentFolder !== null ? this.currentFolder.versioning.fsPath : '',
      fsType: this.currentFolder !== null ? this.currentFolder.versioning.fsType : 'basic'
    };
  }

  private getVersioningParam(versioning: Versioning, key: string, fallback: string): string {
    const value = versioning.params[key];
    return value === undefined ? fallback : value;
  }

  private normalizeNumber(value: string): string {
    const sanitized = value.trim().replace(/[^0-9]/g, '');
    return sanitized.length === 0 ? '0' : sanitized;
  }

  private parsePositiveInt(value: string, fallback: number): number {
    const parsed = Number.parseInt(value, 10);
    if (Number.isNaN(parsed) || parsed < 0) {
      return fallback;
    }
    return parsed;
  }

  private ensureVersioningDefaults(type: string): void {
    if (type === 'simple' && this.versionKeep.length === 0) {
      this.versionKeep = '5';
    }
    if ((type === 'simple' || type === 'trashcan') && this.versionCleanoutDays.length === 0) {
      this.versionCleanoutDays = '0';
    }
    if (type === 'staggered' && this.versionMaxAgeDays.length === 0) {
      this.versionMaxAgeDays = '0';
    }
  }

  private createFallbackFolder(): Folder {
    const versioning: Versioning = {
      type: '',
      params: {},
      fsPath: '',
      fsType: 'basic'
    };
    return {
      id: '',
      label: '',
      filesystemType: 'basic',
      path: '',
      type: 'sendreceive',
      devices: [],
      rescanIntervalS: 3600,
      fsWatcherEnabled: true,
      fsWatcherDelayS: 10,
      ignorePerms: false,
      autoNormalize: true,
      minDiskFreePct: 1,
      minDiskFree: { value: 1, unit: '%' },
      versioning,
      copiers: 0,
      pullers: 0,
      hashers: 0,
      order: 'random',
      ignoreDelete: false,
      scanProgressIntervalS: 0,
      pullerPauseS: 0,
      maxConflicts: 10,
      maxConcurrentWrites: 16,
      disableSparseFiles: false,
      disableTempIndexes: false,
      pinned: false,
      markerName: '.stfolder',
      copyOwnershipFromParent: false,
      copyRangeMethod: 'standard',
      modTimeWindowS: 0,
      paused: false
    };
  }

  private validateFolder(): boolean {
    if (this.folderId.length === 0) {
      this.showToast('Folder ID is required');
      return false;
    }
    if (this.path.length === 0) {
      this.showToast('Folder path is required');
      return false;
    }
    return true;
  }

  private async verifyFolderSaved(folderId: string): Promise<boolean> {
    if (this.restApi === null) {
      return false;
    }
    const result = await this.restApi.getFolder(folderId);
    if (result.success && result.data !== undefined) {
      Logger.i(TAG, `Folder save verified: ${folderId}`);
      return true;
    }
    Logger.e(TAG, `Folder verification failed: ${result.error}`);
    return false;
  }

  private updateDeviceShare(deviceId: string, shared: boolean, encryptionPassword: string): void {
    const updated: DeviceShareState[] = [];
    for (let i = 0; i < this.deviceShares.length; i++) {
      const current = this.deviceShares[i];
      const next = new DeviceShareState();
      next.deviceId = current.deviceId;
      next.name = current.name;
      next.shared = current.deviceId === deviceId ? shared : current.shared;
      next.encryptionPassword = current.deviceId === deviceId ? encryptionPassword : current.encryptionPassword;
      updated.push(next);
    }
    this.deviceShares = updated;
  }

  private setAllDeviceShares(shared: boolean): void {
    const updated: DeviceShareState[] = [];
    for (let i = 0; i < this.deviceShares.length; i++) {
      const current = this.deviceShares[i];
      const next = new DeviceShareState();
      next.deviceId = current.deviceId;
      next.name = current.name;
      next.shared = shared;
      next.encryptionPassword = current.encryptionPassword;
      updated.push(next);
    }
    this.deviceShares = updated;
  }

  private selectedDeviceShareCount(): number {
    let count = 0;
    for (let i = 0; i < this.deviceShares.length; i++) {
      if (this.deviceShares[i].shared) {
        count++;
      }
    }
    return count;
  }

  private getLocalDeviceId(): string {
    if (this.localDeviceId.length > 0) {
      return this.localDeviceId;
    }
    if (this.currentFolder !== null && this.currentFolder.devices.length > 0) {
      return this.getFolderDeviceId(this.currentFolder.devices[0]);
    }
    return '';
  }

  private getDeviceId(device: Device): string {
    if (device.deviceID !== undefined && device.deviceID.length > 0) {
      return device.deviceID;
    }
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    return '';
  }

  private getFolderDeviceId(device: FolderDevice): string {
    if (device.deviceID !== undefined && device.deviceID.length > 0) {
      return device.deviceID;
    }
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    return '';
  }

  private normalizeFolderId(value: string): string {
    return value.trim().toLowerCase().replace(/[^a-z0-9._-]/g, '-');
  }

  private suggestFolderId(): string {
    return `sync-${Date.now().toString(36)}`;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }
}
