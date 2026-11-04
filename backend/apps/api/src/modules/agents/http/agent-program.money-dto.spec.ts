import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import {
  CommissionsQueryDto,
  DeviceDto,
  PayoutsQueryDto,
} from './agent-program.dto';

const FCM = 'f'.repeat(40);
const problems = (cls: new () => object, value: object) =>
  validateSync(plainToInstance(cls, value), {
    whitelist: true,
    forbidNonWhitelisted: true,
  }).map((e) => e.property);

describe('money route DTOs', () => {
  it('DeviceDto accepts ANDROID and IOS only', () => {
    expect(problems(DeviceDto, { fcmToken: FCM, platform: 'ANDROID' })).toEqual(
      [],
    );
    expect(problems(DeviceDto, { fcmToken: FCM, platform: 'IOS' })).toEqual([]);
    for (const platform of ['WEB', 'ios', '', undefined]) {
      expect(problems(DeviceDto, { fcmToken: FCM, platform })).toEqual([
        'platform',
      ]);
    }
  });

  it('DeviceDto checks the token length (20 to 4096)', () => {
    expect(
      problems(DeviceDto, { fcmToken: 'x'.repeat(20), platform: 'IOS' }),
    ).toEqual([]);
    expect(
      problems(DeviceDto, { fcmToken: 'x'.repeat(4096), platform: 'IOS' }),
    ).toEqual([]);
    expect(
      problems(DeviceDto, { fcmToken: 'x'.repeat(19), platform: 'IOS' }),
    ).toEqual(['fcmToken']);
    expect(
      problems(DeviceDto, { fcmToken: 'x'.repeat(4097), platform: 'IOS' }),
    ).toEqual(['fcmToken']);
  });

  it('CommissionsQueryDto accepts the public statuses only', () => {
    for (const status of ['ON_HOLD', 'APPROVED', 'PAID', 'CANCELLED']) {
      expect(problems(CommissionsQueryDto, { status })).toEqual([]);
    }
    for (const status of ['IN_REVIEW', 'REVERSED', 'FROZEN', 'on_hold']) {
      expect(problems(CommissionsQueryDto, { status })).toEqual(['status']);
    }
  });

  it('the page size is 1 to 50 on both lists', () => {
    for (const cls of [CommissionsQueryDto, PayoutsQueryDto]) {
      expect(problems(cls, { limit: '1' })).toEqual([]);
      expect(problems(cls, { limit: '50' })).toEqual([]);
      expect(problems(cls, { limit: '0' })).toEqual(['limit']);
      expect(problems(cls, { limit: '51' })).toEqual(['limit']);
    }
  });
});
