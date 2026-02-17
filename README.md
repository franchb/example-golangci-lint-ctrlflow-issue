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

The bug triggers when the golangci-lint analysis cache is partially stale (some fact files present, some missing). If the first run succeeds, force partial cache invalidation:

```bash
# Clear the Go build cache but keep golangci-lint's analysis cache
go clean -cache
./custom-gcl run -v
```

Or delete some of the cached fact files:

```bash
find ~/.cache/golangci-lint -type f | shuf | head -n $(( $(find ~/.cache/golangci-lint -type f | wc -l) / 2 )) | xargs rm -f
./custom-gcl run -v
```

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
