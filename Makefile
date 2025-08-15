SHELL=/bin/bash

.PHONY: all
all: test
	shards build

.PHONY: test
test:
	crystal spec --error-trace --order random --verbose -Dpreview_mt -Dexecution_context --
