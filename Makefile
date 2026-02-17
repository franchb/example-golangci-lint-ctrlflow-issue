.PHONY: reproduce clean clean-reproduce step1 step2

# Two-step reproduction:
#   Step 1: populate cache with standard linters (ctrlflow facts get cached)
#   Step 2: add nilaway — triggers panic because markDepsForAnalyzingSource is not recursive
reproduce: custom-gcl
	@echo "=== Step 1: Clean cache and run WITHOUT nilaway to populate ctrlflow facts cache ==="
	./custom-gcl cache clean
	./custom-gcl run -v -c .golangci-step1.yml || true
	@echo ""
	@echo "=== Step 2: Run WITH nilaway on warm cache — triggers buildssa panic ==="
	@echo ""
	./custom-gcl run -v
	@echo ""
	@echo "If you see 'interface conversion: interface {} is nil, not *ctrlflow.CFGs' above, the bug is reproduced."

# For comparison: clean cache + nilaway works fine
clean-reproduce: custom-gcl
	@echo "=== Clean cache + nilaway: this works fine (no panic) ==="
	./custom-gcl cache clean
	./custom-gcl run -v

custom-gcl: .custom-gcl.yml
	golangci-lint custom -v

clean:
	rm -f custom-gcl
	golangci-lint cache clean 2>/dev/null || true
