// Blocks I/O that needs no import, so dependency-cruiser can't see it: global fetch,
// process (env, argv, exit) and friends. Applies to domain and application only.
// Use: import boundaries from "./eslint.boundaries.js"; then add ...boundaries to your
// eslint.config.js array. Adjust the paths to your layout. Rename to .mjs if your
// package.json is not "type": "module".
const CORE = ["src/domain/**", "src/application/**"];
const why = "domain and application must not do I/O; inject it from infrastructure.";

const GLOBALS = ["fetch", "XMLHttpRequest", "WebSocket", "EventSource", "process", "require", "Bun", "Deno"];

export default [
  {
    files: CORE,
    rules: {
      "no-restricted-globals": ["error", ...GLOBALS.map((name) => ({ name, message: why }))],
      "no-restricted-properties": [
        "error",
        ...GLOBALS.map((property) => ({ object: "globalThis", property, message: why })),
      ],
    },
  },
];
