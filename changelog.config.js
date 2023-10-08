// https://github.com/conventional-changelog/conventional-changelog-config-spec/blob/master/versions/2.2.0/schema.json
const Configuration = {
  options: {
    preset: {
      name: "conventionalcommits",
      header: "Changelog",
      issueUrlFormat: "https://github.com/mkoertgen/scooped/issues/{{id}}",
      commitUrlFormat: "https://github.com/mkoertgen/scooped/commit/{{hash}}",
      compareUrlFormat:
        "https://dev.azure.com/colenio/vertec/_git/vertec/branchCompare?baseVersion=GT{{previousTag}}&targetVersion=GT{{currentTag}}",
      types: [
        { type: "feat", section: "Features" },
        { type: "fix", section: "Bug Fixes" },
        // hidden types
        { type: "perf", hidden: true },
        { type: "revert", hidden: true },
        { type: "docs", hidden: true },
        { type: "style", hidden: true },
        { type: "chore", hidden: true },
        { type: "refactor", hidden: true },
        { type: "test", hidden: true },
        { type: "build", hidden: true },
        { type: "ci", hidden: true },
      ],
    },
  },
};

module.exports = Configuration;
