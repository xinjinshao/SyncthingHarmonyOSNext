import { Logger } from '../common/Logger';
import { DeviceListPage } from './DeviceListPage';
import { FolderListPage } from './FolderListPage';
import { StatusPage } from './StatusPage';

const TAG = 'MainPage';

@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 0;
  @State serviceState: string = 'unknown';
  private tabTitles: string[] = ['Devices', 'Folders', 'Status'];

  aboutToAppear(): void {
    Logger.i(TAG, 'MainPage appearing');
  }

  build() {
    Column() {
      Row() {
        Text('Syncthing')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 16 })
          .layoutWeight(1)

        Row({ space: 12 }) {
          Image($r('app.media.syncthing'))
            .width(24)
            .height(24)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' });
            })
        }
        .margin({ right: 16 })
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Tabs({ index: this.currentTabIndex }) {
        TabContent() {
          DeviceListPage()
        }
        .tabBar(this.tabBarBuilder('Devices', 0))

        TabContent() {
          FolderListPage()
        }
        .tabBar(this.tabBarBuilder('Folders', 1))

        TabContent() {
          StatusPage()
        }
        .tabBar(this.tabBarBuilder('Status', 2))
      }
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(48)
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  tabBarBuilder(title: string, index: number) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(index === this.currentTabIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.currentTabIndex ? '#007AFF' : '#999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }
}
