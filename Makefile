.PHONY: bootstrap generate build test-core test-app test-db test-integration db-reset test

bootstrap:
	scripts/bootstrap.sh

generate:
	xcodegen generate

build: generate
	scripts/build-app.sh

test-core:
	scripts/test-core.sh

test-app: generate
	scripts/test-app.sh

db-reset:
	supabase db reset

test-db:
	supabase test db

test-integration: generate
	scripts/test-integration.sh

test: test-core test-db test-integration
