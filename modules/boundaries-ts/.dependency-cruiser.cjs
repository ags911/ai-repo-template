/** Enforces the layer rules in ARCHITECTURE.md. Adjust paths to your layout. */

// Packages that are infrastructure: drivers, ORMs, HTTP servers and clients, cloud SDKs.
// Domain and application code must not import them. Edit this list for your project.
const INFRA_PACKAGES = [
  "pg", "mysql2", "sqlite3", "better-sqlite3", "mongodb", "mongoose", "redis", "ioredis",
  "@prisma/client", "typeorm", "sequelize", "drizzle-orm", "knex",
  "express", "fastify", "koa", "@nestjs/core", "next", "axios", "node-fetch",
  "@aws-sdk/[^/]+", "@google-cloud/[^/]+", "@azure/[^/]+",
];
// Matches the package under node_modules, including pnpm's node_modules/.pnpm layout.
const infraPackagePath = `(^|/)node_modules/(${INFRA_PACKAGES.join("|")})(/|$)`;

module.exports = {
  forbidden: [
    {
      name: "domain-is-pure",
      severity: "error",
      from: { path: "^src/domain" },
      to: { path: "^src/(application|infrastructure|presentation)" },
    },
    {
      name: "application-not-infrastructure",
      severity: "error",
      from: { path: "^src/application" },
      to: { path: "^src/(infrastructure|presentation)" },
    },
    {
      name: "presentation-not-infrastructure",
      severity: "error",
      from: { path: "^src/presentation" },
      to: { path: "^src/infrastructure" },
    },
    {
      // Catches domain reaching infrastructure indirectly, e.g. through a barrel file
      // (src/shared/index.ts re-exporting an infrastructure module).
      name: "domain-not-reach-infrastructure",
      severity: "error",
      from: { path: "^src/domain" },
      to: { path: "^src/infrastructure", reachable: true },
    },
    {
      name: "core-no-infra-packages",
      comment: "domain and application must not import infrastructure packages (see INFRA_PACKAGES)",
      severity: "error",
      from: { path: "^src/(domain|application)" },
      to: { path: infraPackagePath },
    },
    {
      name: "core-no-io-builtins",
      comment: "domain and application must not do I/O directly (network, files, processes)",
      severity: "error",
      from: { path: "^src/(domain|application)" },
      to: {
        dependencyTypes: ["core"],
        path: "^(node:)?(fs|fs/promises|http|https|http2|net|tls|dgram|dns|child_process|cluster|worker_threads)$",
      },
    },
    {
      name: "no-circular",
      severity: "error",
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: "tsconfig.json" },
  },
};
