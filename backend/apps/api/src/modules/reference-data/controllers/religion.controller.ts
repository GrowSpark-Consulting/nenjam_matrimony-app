import { Controller, Get, Query } from '@nestjs/common';
import {
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { ReligionService } from '../services/religion.service';
import {
  CommunitiesQueryDto,
  ReligionsQueryDto,
} from '../dto/religion.query.dto';
import { CommunityDto, ReligionDto } from '../dto/religion.response.dto';

/**
 * Public reference data — deliberately NOT behind FirebaseAuthGuard, for the
 * same reason as the location routes: the Religion step runs during
 * registration, before a member has a session at all (auth is the last
 * onboarding step). Requiring a token would make the dropdown unfillable for
 * exactly the people who need it, and there is nothing to protect — these are
 * the same lists the app already shipped in its binary.
 *
 * ThrottlerGuard still applies; it is registered globally as an APP_GUARD.
 */
@ApiTags('Reference data')
@Controller('reference-data')
export class ReligionController {
  constructor(private readonly religions: ReligionService) {}

  @Get('religions')
  @ApiOperation({
    summary: 'List selectable religions',
    description: 'Active religions, alphabetical.',
  })
  @ApiOkResponse({ type: [ReligionDto] })
  listReligions(@Query() query: ReligionsQueryDto): Promise<ReligionDto[]> {
    return this.religions.listReligions(query.includeInactive);
  }

  @Get('communities')
  @ApiOperation({
    summary: 'List communities within a religion',
    description:
      'Active communities for the given religion, alphabetical. A religion ' +
      'with no communities returns an empty array; an unknown religion 404s.',
  })
  @ApiOkResponse({ type: [CommunityDto] })
  @ApiNotFoundResponse({ description: 'Unknown religion code.' })
  listCommunities(@Query() query: CommunitiesQueryDto): Promise<CommunityDto[]> {
    return this.religions.listCommunities(query.religionCode, query.includeInactive);
  }
}
