.PHONY: run test build fmt vet tidy

run:
	go run .

test:
	go test -race ./...

build:
	go build -o bin/api .

fmt:
	gofmt -w .

vet:
	go vet ./...

tidy:
	go mod tidy
