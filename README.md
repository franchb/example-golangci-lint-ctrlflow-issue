# Reproducer for golangci-lint buildssa panic with nilaway plugin

This repository is a minimal reproducer for a bug in golangci-lint's analysis runner. When using the nilaway custom plugin, `buildssa` panics for non-initial (dependency) packages.

## Error

```
buildssa: package "goarch" (isInitialPkg: false, needAnalyzeSource: true): interface conversion: interface {} is nil, not *ctrlflow.CFGs
```

The panicking package varies between runs — `goarch`, `unicode`, `kbin` (from franz-go), etc.

## Prerequisites

- Go 1.26+
- golangci-lint v2.9.0+ (`go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.10.0`)

## Steps to reproduce

```bash
git clone https://github.com/franchb/example-golangci-lint-ctrlflow-issue.git
cd example-golangci-lint-ctrlflow-issue
make reproduce
```

`make reproduce` runs two steps automatically:

1. **Step 1** — runs standard linters (bodyclose, staticcheck, govet, etc.) which populate the `ctrlflow` facts cache for dependency packages.
2. **Step 2** — adds nilaway. Nilaway has no cached facts, so `loadCachedFacts()` fails. This calls `markDepsForAnalyzingSource()` which marks `buildssa.needAnalyzeSource = true`. But `markDepsForAnalyzingSource` is not recursive — it doesn't mark `ctrlflow`. Since ctrlflow's facts were cached in step 1, ctrlflow is NOT in the "failed facts" loop, so its `needAnalyzeSource` stays `false`. In the analyze phase, ctrlflow skips execution (returns nil Result), and buildssa panics.

For comparison, `make clean-reproduce` runs with a clean cache where the bug does NOT occur — proving the cache-dependent nature of the issue.

### Why two steps are needed

The bug requires a **partially populated analysis cache**. It does NOT reproduce on a clean cache.

With a clean cache, ALL analyzers fail facts loading, so ctrlflow itself gets marked for source analysis and runs fine. The bug only occurs when ctrlflow's facts are cached (from a previous run with standard linters) but a new analyzer (nilaway) that transitively depends on ctrlflow fails facts loading.

This matches real-world usage: projects typically run golangci-lint in CI with a set of linters, and adding nilaway later triggers the panic because the cache already has ctrlflow facts but not nilaway facts.

## Expected result

nilaway analyzes the code and reports findings (or no findings).

## Actual result

Panic in `buildssa` for a non-initial package:

```
ERRO [linters_context/goanalysis] buildssa: panic during analysis: interface conversion: interface {} is nil, not *ctrlflow.CFGs
WARN [runner] Can't run linter goanalysis_metalinter: goanalysis_metalinter: buildssa: package "goarch" (isInitialPkg: false, needAnalyzeSource: true): interface conversion: interface {} is nil, not *ctrlflow.CFGs
```

## Root cause

`markDepsForAnalyzingSource()` in `pkg/goanalysis/runner_action.go` only marks **direct** horizontal deps for source analysis — it does not recurse into transitive deps.

The analyzer dependency chain is: `nilaway -> buildssa -> ctrlflow -> inspect`

When nilaway fails cached facts loading for a non-initial package:

1. nilaway calls `markDepsForAnalyzingSource()`, marking `buildssa.needAnalyzeSource = true`
2. But `buildssa.markDepsForAnalyzingSource()` is never called
3. So `ctrlflow.needAnalyzeSource` stays `false`
4. In the analyze phase, `ctrlflow` returns immediately with nil `Result`
5. `buildssa` panics: `pass.ResultOf[ctrlflow.Analyzer].(*ctrlflow.CFGs)` on nil

## Suggested fix

Make `markDepsForAnalyzingSource` recursive:

```go
func (act *action) markDepsForAnalyzingSource() {
    for _, dep := range act.Deps {
        if dep.Package == act.Package && !dep.needAnalyzeSource {
            dep.needAnalyzeSource = true
            dep.markDepsForAnalyzingSource()
        }
    }
}
```

## Affected versions

golangci-lint v2.9.0, v2.10.0 (any version using `golang.org/x/tools` >= v0.40.0 where `buildssa` depends on `ctrlflow`).
