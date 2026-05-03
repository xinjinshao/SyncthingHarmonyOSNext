export interface Event {
  id: number;
  globalId: number;
  time: string;
  type: string;
  data: Object;
}

export interface DiskEvent {
  id: number;
  time: string;
  type: string;
  data: Object;
}

export type EventData = Object;
