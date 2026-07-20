// Mapped from Prisma's AstrologyProfile row by ProfileRepository.
export class AstrologyProfileEntity {
  id!: string;
  userId!: string;
  birthDate!: Date;
  birthTime!: string | null;
  birthPlace!: string | null;
  rasi!: string | null;
  nakshatra!: string | null;
  lagnam!: string | null;
  gotram!: string | null;
  dosham!: string;
  horoscopeAvailable!: boolean;
}
