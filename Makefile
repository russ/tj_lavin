SHELL=/bin/bash

.PHONY: all
all: test
	shards build

.PHONY: test
test:
	AMQP_URL=amqp://guest:guest@localhost:5672 crystal spec --error-trace --order random --verbose -Dpreview_mt -Dexecution_context --
