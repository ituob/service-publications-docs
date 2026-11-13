// Runs the GENERATED TypeScript validators over JSON cases.
//   node --experimental-strip-types ts_validator_check.mjs <validators.ts> <cases.json>
// cases.json: [{ id, class, value }]. Prints {id, issues} for every case.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const [modulePath, casesPath] = process.argv.slice(2);
const mod = await import(pathToFileURL(resolve(modulePath)).href);
const cases = JSON.parse(readFileSync(casesPath, "utf8"));
const results = cases.map((c) => ({ id: c.id, issues: mod.validateClass(c.class, c.value) }));
process.stdout.write(JSON.stringify(results));
