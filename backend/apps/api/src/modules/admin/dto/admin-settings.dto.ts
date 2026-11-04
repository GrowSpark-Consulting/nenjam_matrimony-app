import { ApiProperty } from '@nestjs/swagger';
import { Allow, IsInt, Min } from 'class-validator';
import { AdminReasonDto } from './admin-membership.dto';

export class UpdatePlatformSettingDto extends AdminReasonDto {
  @ApiProperty({
    description:
      'The new value: any JSON, `null` included ("not decided"). The feature that reads the key may refuse values it cannot use.',
  })
  @Allow()
  value!: unknown;

  @ApiProperty({
    description: 'The version you loaded; 409 if it changed since.',
    minimum: 1,
  })
  @IsInt()
  @Min(1)
  version!: number;
}
