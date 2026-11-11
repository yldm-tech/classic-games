module github.com/yldm-tech/classic-games/apps/cli

go 1.26.0

require (
	github.com/santhosh-tekuri/jsonschema/v6 v6.0.2
	github.com/spf13/cobra v1.10.2
	github.com/yldm-tech/classic-games/packages/dsl v0.0.0
	github.com/yldm-tech/classic-games/packages/sdk v0.0.0
	golang.org/x/text v0.43.0
)

require (
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/spf13/pflag v1.0.9 // indirect
)

replace github.com/yldm-tech/classic-games/packages/dsl => ../../packages/dsl

replace github.com/yldm-tech/classic-games/packages/sdk => ../../packages/sdk
