import js from "@eslint/js";
import tseslint from "typescript-eslint";
// Copied in from modules/boundaries-ts by selftest/run.sh, like .dependency-cruiser.cjs.
import boundaries from "./eslint.boundaries.js";

export default tseslint.config(
  { ignores: ["node_modules/"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...boundaries,
  {
    // .dependency-cruiser.cjs is CommonJS
    files: ["**/*.cjs"],
    languageOptions: { sourceType: "commonjs", globals: { module: "writable", require: "readonly" } },
  },
);
