import { Logger } from '../common/Logger';
import { PreferencesManager } from '../data/PreferencesManager';
import { Folder } from '../model/Index';
import { RestApi } from '../network/RestApi';
import { Constants } from './Constants';
import { FolderLocationManager, FolderLocationMapping } from './FolderLocationManager';
import { FolderMirrorResult, FolderMirrorService } from './FolderMirrorService';

const TAG = 'FolderMirrorScheduler';

/**
 * Periodically imports mapped external folders into their Syncthing sandbox mirrors.
 */
export class FolderMirrorScheduler {
  private restApi: RestApi;
  private locationManager: FolderLocationManager;
  private mirrorService: FolderMirrorService = new FolderMirrorService();
  private timer: number | null = null;
  private running: boolean = false;
  private tickActive: boolean = false;

  constructor(restApi: RestApi, preferences: PreferencesManager) {
    this.restApi = restApi;
    this.locationManager = new FolderLocationManager(preferences);
  }

  start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.schedule(5000);
    Logger.i(TAG, 'Folder mirror scheduler started');
  }

  stop(): void {
    this.running = false;
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    Logger.i(TAG, 'Folder mirror scheduler stopped');
  }

  private schedule(delayMs: number): void {
    if (!this.running || this.timer !== null) {
      return;
    }
    this.timer = setTimeout(() => {
      this.timer = null;
      this.tick();
    }, delayMs);
  }

  private async tick(): Promise<void> {
    if (!this.running || this.tickActive) {
      this.schedule(Constants.FOLDER_MIRROR_INTERVAL_MS);
      return;
    }
    this.tickActive = true;
    try {
      const mappings = await this.locationManager.getAllExternalMappings();
      for (let i = 0; i < mappings.length; i++) {
        await this.processMapping(mappings[i]);
      }
    } catch (err) {
      Logger.w(TAG, `Mirror tick failed: ${JSON.stringify(err)}`);
    } finally {
      this.tickActive = false;
      this.schedule(Constants.FOLDER_MIRROR_INTERVAL_MS);
    }
  }

  private async processMapping(mapping: FolderLocationMapping): Promise<void> {
    const folderResult = await this.restApi.getFolder(mapping.folderId);
    if (!folderResult.success || folderResult.data === undefined) {
      return;
    }
    const folder: Folder = folderResult.data;
    if (folder.paused || folder.type === Constants.FOLDER_TYPE_RECEIVE_ONLY || folder.type === Constants.FOLDER_TYPE_RECEIVE_ENCRYPTED) {
      return;
    }

    const result: FolderMirrorResult = await this.mirrorService.importExternalToSandbox(mapping);
    if (result.success && result.copiedFiles > 0) {
      Logger.i(TAG, `Imported ${result.copiedFiles} files for ${mapping.folderId}`);
      await this.restApi.scanFolder(mapping.folderId);
    }
  }
}
