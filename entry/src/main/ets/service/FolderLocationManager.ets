import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from './Constants';

const TAG = 'FolderLocationManager';

export class FolderLocationMapping {
  folderId: string = '';
  externalUri: string = '';
  syncthingPath: string = '';
}

/**
 * Stores the mapping between Harmony picker URIs and Syncthing-readable paths.
 *
 * The Go core scans sandbox paths only. When the user chooses a system folder,
 * this manager persists the external URI separately and gives Syncthing a mirror
 * path under app storage.
 */
export class FolderLocationManager {
  private preferences: PreferencesManager;

  constructor(preferences: PreferencesManager) {
    this.preferences = preferences;
  }

  async getMapping(folderId: string): Promise<FolderLocationMapping> {
    const mapping = new FolderLocationMapping();
    mapping.folderId = folderId;
    if (folderId.length === 0) {
      return mapping;
    }
    mapping.externalUri = await this.preferences.getString(Constants.DYN_PREF_FOLDER_LOCATION_EXTERNAL_URI(folderId), '');
    mapping.syncthingPath = await this.preferences.getString(Constants.DYN_PREF_FOLDER_LOCATION_SYNC_PATH(folderId), '');
    return mapping;
  }

  async saveExternalMapping(folderId: string, externalUri: string, syncthingPath: string): Promise<void> {
    if (folderId.length === 0 || externalUri.length === 0 || syncthingPath.length === 0) {
      return;
    }
    await this.preferences.putString(Constants.DYN_PREF_FOLDER_LOCATION_EXTERNAL_URI(folderId), externalUri);
    await this.preferences.putString(Constants.DYN_PREF_FOLDER_LOCATION_SYNC_PATH(folderId), syncthingPath);
    await this.addExternalFolderId(folderId);
    Logger.i(TAG, `Saved external folder mapping: ${folderId}`);
  }

  async clearMapping(folderId: string): Promise<void> {
    if (folderId.length === 0) {
      return;
    }
    await this.preferences.remove(Constants.DYN_PREF_FOLDER_LOCATION_EXTERNAL_URI(folderId));
    await this.preferences.remove(Constants.DYN_PREF_FOLDER_LOCATION_SYNC_PATH(folderId));
    await this.removeExternalFolderId(folderId);
    Logger.i(TAG, `Cleared external folder mapping: ${folderId}`);
  }

  async getAllExternalMappings(): Promise<FolderLocationMapping[]> {
    const ids = await this.getExternalFolderIds();
    const mappings: FolderLocationMapping[] = [];
    for (let i = 0; i < ids.length; i++) {
      const mapping = await this.getMapping(ids[i]);
      if (mapping.externalUri.length > 0 && mapping.syncthingPath.length > 0) {
        mappings.push(mapping);
      }
    }
    return mappings;
  }

  getSandboxPath(folderId: string): string {
    return `/data/storage/el2/base/files/${folderId}`;
  }

  async ensureSyncthingFolder(path: string): Promise<boolean> {
    if (path.length === 0 || path.indexOf('://') >= 0) {
      return false;
    }
    try {
      if (!this.pathExists(path)) {
        await fileIo.mkdir(path, true);
      }
      const markerPath = `${path}/${Constants.FILENAME_STFOLDER}`;
      if (!this.pathExists(markerPath)) {
        await fileIo.mkdir(markerPath, true);
      }
      return true;
    } catch (err) {
      Logger.e(TAG, `Failed to prepare Syncthing folder path '${path}': ${JSON.stringify(err)}`);
      return false;
    }
  }

  private pathExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private async getExternalFolderIds(): Promise<string[]> {
    const encoded = await this.preferences.getString(Constants.PREF_FOLDER_LOCATION_EXTERNAL_IDS, '');
    if (encoded.length === 0) {
      return [];
    }
    const rawIds = encoded.split('|');
    const ids: string[] = [];
    for (let i = 0; i < rawIds.length; i++) {
      const id = rawIds[i].trim();
      if (id.length > 0 && !this.containsId(ids, id)) {
        ids.push(id);
      }
    }
    return ids;
  }

  private async addExternalFolderId(folderId: string): Promise<void> {
    const ids = await this.getExternalFolderIds();
    if (!this.containsId(ids, folderId)) {
      ids.push(folderId);
      await this.preferences.putString(Constants.PREF_FOLDER_LOCATION_EXTERNAL_IDS, ids.join('|'));
    }
  }

  private async removeExternalFolderId(folderId: string): Promise<void> {
    const ids = await this.getExternalFolderIds();
    const remaining: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== folderId) {
        remaining.push(ids[i]);
      }
    }
    await this.preferences.putString(Constants.PREF_FOLDER_LOCATION_EXTERNAL_IDS, remaining.join('|'));
  }

  private containsId(ids: string[], folderId: string): boolean {
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === folderId) {
        return true;
      }
    }
    return false;
  }
}
