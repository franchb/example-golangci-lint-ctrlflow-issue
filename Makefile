.PHONY: reproduce clean

reproduce: custom-gcl
	./custom-gcl run -v

custom-gcl: .custom-gcl.yml
	golangci-lint custom -v
	@echo ""
	@echo "Custom binary built. Now running linter..."
	@echo ""

clean:
	rm -f custom-gcl
