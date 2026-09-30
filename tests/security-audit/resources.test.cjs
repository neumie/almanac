const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const skillDir = path.resolve(__dirname, "../../skills/other/security-audit");

// The guides must remain navigable after their move into references/.
test("bundled Markdown links resolve inside the skill directory", () => {
  const documents = [
    path.join(skillDir, "SKILL.md"),
    ...fs.readdirSync(path.join(skillDir, "references"))
      .filter((name) => name.endsWith(".md"))
      .map((name) => path.join(skillDir, "references", name)),
  ];
  for (const document of documents) {
    const text = fs.readFileSync(document, "utf8");
    for (const match of text.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
      const href = match[1];
      if (/^https?:\/\//.test(href) || href.startsWith("#")) continue;
      const target = path.resolve(path.dirname(document), href.split("#")[0]);
      assert(target.startsWith(`${skillDir}${path.sep}`), `${document}: escaping link ${href}`);
      assert(fs.statSync(target).isFile(), `${document}: missing resource ${href}`);
    }
  }
});

for (const root of [".agents/skills/almanac", ".claude/skills/almanac"]) {
  test(`validators work through ${root} directory symlinks from an unrelated cwd`, () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "security-audit-install-"));
    try {
      const installed = path.join(directory, root, "security-audit");
      fs.mkdirSync(path.dirname(installed), { recursive: true });
      fs.symlinkSync(skillDir, installed, "dir");
      const input = path.join(directory, "empty.json");
      fs.writeFileSync(input, "[]");
      for (const name of ["validate-findings.cjs", "validate-coverage-ledger.cjs"]) {
        const result = spawnSync(process.execPath, [path.join(installed, "scripts", name), input], {
          cwd: directory,
          encoding: "utf8",
          timeout: 5000,
        });
        assert.ifError(result.error);
        assert.equal(result.status, 0, `${name}: ${result.stdout}${result.stderr}`);
      }
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });
}
