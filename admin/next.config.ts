import type { NextConfig } from 'next';

/**
 * A static export: the admin panel is plain HTML/JS calling the NestJS API.
 * It has no server of its own, holds no secrets, and can be hosted on any
 * static host (see README.md). Every authorisation decision is made by the
 * API; this app only hides what /admin/me says the admin can't use.
 */
const config: NextConfig = {
  output: 'export',
  reactStrictMode: true,
  poweredByHeader: false,
  trailingSlash: true,
};

export default config;
