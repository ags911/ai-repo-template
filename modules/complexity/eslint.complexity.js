// Size and complexity limits for TypeScript (complexity module). They are fitness functions:
// verify fails when code grows past them. Set the numbers for your project, then
// import complexity from "./eslint.complexity.js"; and add ...complexity to eslint.config.js.
// Rename to .mjs if your package.json is not "type": "module".
const LIMITS = {
  complexity: 10, // independent paths through one function
  depth: 4, // nested blocks
  params: 4, // parameters per function
  functionLines: 60, // lines per function, not counting blanks and comments
  fileLines: 400, // lines per file, not counting blanks and comments
};

export default [
  {
    files: ["src/**/*.{ts,tsx}"],
    ignores: ["**/*.test.*", "**/*.spec.*"],
    rules: {
      complexity: ["error", LIMITS.complexity],
      "max-depth": ["error", LIMITS.depth],
      "max-params": ["error", LIMITS.params],
      "max-lines-per-function": ["error", { max: LIMITS.functionLines, skipBlankLines: true, skipComments: true }],
      "max-lines": ["error", { max: LIMITS.fileLines, skipBlankLines: true, skipComments: true }],
    },
  },
];
