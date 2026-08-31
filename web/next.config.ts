import type { NextConfig } from 'next'

const apiPort = process.env.API_PORT

if (!apiPort) {
  throw new Error("API_PORT is not set")
}

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: "/rpc/:path*",
        destination: `http://api:${apiPort}/:path*`,
      },
    ];
  },
}

export default nextConfig
