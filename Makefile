.PHONY: bootstrap generate build test-core test-app test-db db-reset test

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

test: test-core test-db test-app
