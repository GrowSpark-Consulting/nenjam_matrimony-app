import { Controller, Get, Query } from '@nestjs/common';
import {
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { LocationService } from '../services/location.service';
import {
  CitiesQueryDto,
  CountriesQueryDto,
  StatesQueryDto,
} from '../dto/location.query.dto';
import { CityDto, CountryDto, SubdivisionDto } from '../dto/location.response.dto';

/**
 * Public reference data — deliberately NOT behind FirebaseAuthGuard.
 *
 * The location step happens during registration, before a member has a
 * profile and, in the mobile+password flow, potentially before a session
 * exists at all. Requiring a token here would make the country dropdown
 * unfillable for exactly the people who need it. There is nothing to protect:
 * these are ISO 3166 codes and city names, identical for every caller, derived
 * from a public dataset, and no row is user-specific.
 *
 * Rate limiting still applies — ThrottlerGuard is registered globally as an
 * APP_GUARD, so an unauthenticated caller cannot hammer these endpoints.
 */
@ApiTags('Reference data')
@Controller('reference-data')
export class LocationController {
  constructor(private readonly locations: LocationService) {}

  @Get('countries')
  @ApiOperation({
    summary: 'List selectable countries',
    description:
      'Active countries, alphabetical. Pass includeInactive=true only to resolve ' +
      'a code already stored on a profile.',
  })
  @ApiOkResponse({ type: [CountryDto] })
  listCountries(@Query() query: CountriesQueryDto): Promise<CountryDto[]> {
    return this.locations.listCountries(query.includeInactive);
  }

  @Get('states')
  @ApiOperation({
    summary: 'List states / provinces in a country',
    description:
      'Active subdivisions of the given country, alphabetical. Every one returned ' +
      'has at least one city behind it, so the next dropdown is never empty.',
  })
  @ApiOkResponse({ type: [SubdivisionDto] })
  @ApiNotFoundResponse({ description: 'Unknown country code.' })
  listStates(@Query() query: StatesQueryDto): Promise<SubdivisionDto[]> {
    return this.locations.listSubdivisions(query.countryCode, query.includeInactive);
  }

  @Get('cities')
  @ApiOperation({
    summary: 'List cities in a state / province',
    description:
      'Largest cities first, so the list is useful before the member types anything. ' +
      'With `search`, prefix matches are ranked above substring matches.',
  })
  @ApiOkResponse({ type: [CityDto] })
  @ApiNotFoundResponse({ description: 'Unknown state code.' })
  listCities(@Query() query: CitiesQueryDto): Promise<CityDto[]> {
    return this.locations.listCities(query.stateCode, {
      search: query.search,
      limit: query.limit,
      offset: query.offset,
    });
  }
}
