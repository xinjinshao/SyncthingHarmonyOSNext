import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';
import { Constants } from './Constants';
import { FolderLocationMapping } from './FolderLocationManager';

const TAG = 'FolderMirrorService';

export class FolderMirrorResult {
  success: boolean = false;
  copiedFiles: number = 0;
  skippedItems: number = 0;
  message: string = '';
}

/**
 * Copies files between authorized Harmony folders and Syncthing sandbox mirrors.
 *
 * This is a compatibility layer for HarmonyOS URI-based storage: it does not
 * provide a true VFS, but it lets selected folders participate through explicit
 * import/export passes while keeping the Go core on normal filesystem paths.
 */
export class FolderMirrorService {
  async importExternalToSandbox(mapping: FolderLocationMapping): Promise<FolderMirrorResult> {
    const result = new FolderMirrorResult();
    if (mapping.externalUri.length === 0 || mapping.syncthingPath.length === 0) {
      result.message = 'No external folder mapping';
      return result;
    }
    try {
      await this.ensureDir(mapping.syncthingPath);
      await this.copyTree(mapping.externalUri, mapping.syncthingPath, result);
      result.success = true;
      result.message = `Imported ${result.copiedFiles} files`;
      return result;
    } catch (err) {
      Logger.e(TAG, `Import failed: ${JSON.stringify(err)}`);
      result.message = 'Import failed';
      return result;
    }
  }

  async exportSandboxToExternal(mapping: FolderLocationMapping): Promise<FolderMirrorResult> {
    const result = new FolderMirrorResult();
    if (mapping.externalUri.length === 0 || mapping.syncthingPath.length === 0) {
      result.message = 'No external folder mapping';
      return result;
    }
    try {
      await this.ensureDir(mapping.externalUri);
      await this.copyTree(mapping.syncthingPath, mapping.externalUri, result);
      result.success = true;
      result.message = `Exported ${result.copiedFiles} files`;
      return result;
    } catch (err) {
      Logger.e(TAG, `Export failed: ${JSON.stringify(err)}`);
      result.message = 'Export failed';
      return result;
    }
  }

  private async copyTree(sourceRoot: string, targetRoot: string, result: FolderMirrorResult): Promise<void> {
    let names: string[] = [];
    try {
      names = await fileIo.listFile(sourceRoot);
    } catch (err) {
      Logger.w(TAG, `Unable to list '${sourceRoot}': ${JSON.stringify(err)}`);
      result.skippedItems++;
      return;
    }
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (this.shouldSkip(name)) {
        result.skippedItems++;
        continue;
      }
      const sourcePath = this.joinPath(sourceRoot, name);
      const targetPath = this.joinPath(targetRoot, name);
      try {
        const stat = await fileIo.stat(sourcePath);
        if (stat.isDirectory()) {
          await this.ensureDir(targetPath);
          await this.copyTree(sourcePath, targetPath, result);
        } else if (stat.isFile()) {
          if (await this.shouldCopyFile(sourcePath, targetPath)) {
            await this.ensureParentDir(targetPath);
            await fileIo.copyFile(sourcePath, targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
            result.copiedFiles++;
          } else {
            result.skippedItems++;
          }
        } else {
          result.skippedItems++;
        }
      } catch (err) {
        Logger.w(TAG, `Skipping mirror item '${sourcePath}': ${JSON.stringify(err)}`);
        result.skippedItems++;
      }
    }
  }

  private async ensureParentDir(path: string): Promise<void> {
    const index = path.lastIndexOf('/');
    if (index <= 0) {
      return;
    }
    await this.ensureDir(path.substring(0, index));
  }

  private async shouldCopyFile(sourcePath: string, targetPath: string): Promise<boolean> {
    if (!this.pathExists(targetPath)) {
      return true;
    }
    try {
      const sourceStat = await fileIo.stat(sourcePath);
      const targetStat = await fileIo.stat(targetPath);
      if (!targetStat.isFile()) {
        return true;
      }
      return sourceStat.size !== targetStat.size || sourceStat.mtime > targetStat.mtime;
    } catch (err) {
      Logger.w(TAG, `Falling back to copy for '${sourcePath}': ${JSON.stringify(err)}`);
      return true;
    }
  }


  private async ensureDir(path: string): Promise<void> {
    if (this.pathExists(path)) {
      return;
    }
    try {
      await fileIo.mkdir(path, true);
    } catch (err) {
      if (!this.pathExists(path)) {
        throw new Error(JSON.stringify(err));
      }
    }
  }

  private pathExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private joinPath(root: string, name: string): string {
    if (root.endsWith('/')) {
      return `${root}${name}`;
    }
    return `${root}/${name}`;
  }

  private shouldSkip(name: string): boolean {
    return name === Constants.FILENAME_STFOLDER || name === Constants.FOLDER_NAME_STVERSIONS || name === '.stignore';
  }
}
