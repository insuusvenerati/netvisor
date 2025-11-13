.PHONY: help build test clean format

help:
	@echo "NetVisor Development Commands"
	@echo ""
	@echo "  make setup-db       - Set up database"
	@echo "  make clean-db       - Clean up database"
	@echo "  make clean-daemon   - Remove daemon config file"
	@echo "  make dump-db        - Dump database to /netvisor"
	@echo "  make dev-server     - Start server dev environment"
	@echo "  make dev-ui         - Start ui"
	@echo "  make dev-daemon     - Start daemon dev environment"
	@echo "  make dev-container  - Start containerized development environment using docker-compose.dev.yml (server + ui + daemon)"
	@echo "  make dev-container-rebuild  - Rebuild and start containerized dev environment"
	@echo "  make dev-container-rebuild-clean  - Rebuild, clean, and start containerized dev environment"
	@echo "  make dev-down       - Stop development containers"
	@echo "  make build          - Build production Docker images (server + daemon)"
	@echo ""
	@echo "  ARMv7l Support (32-bit ARM):"
	@echo "  make build-armv7l-server  - Build server binary for armv7l locally (requires cross-compilation setup)"
	@echo "  make build-armv7l-daemon  - Build daemon binary for armv7l locally (requires cross-compilation setup)"
	@echo "  make build-armv7l   - Build both server and daemon for armv7l"
	@echo "  make build-armv7l-docker-local  - Build armv7l Docker images locally (requires docker buildx)"
	@echo "  make build-armv7l-docker  - Build multi-arch Docker images and push to registry"
	@echo "  make test-armv7l    - Verify armv7l binaries (shows binary info)"
	@echo "  make install-dev-linux-armv7l  - Install armv7l cross-compilation dependencies"
	@echo ""
	@echo "  make test           - Run all tests"
	@echo "  make lint           - Run all linters"
	@echo "  make format         - Format all code"
	@echo "  make clean          - Clean build artifacts and containers"
	@echo "  make install-dev-mac    - Install development dependencies on macOS"
	@echo "  make install-dev-linux  - Install development dependencies on Linux"

setup-db:
	@echo "Setting up PostgreSQL..."
	@docker run -d \
		--name netvisor-postgres \
		-e POSTGRES_USER=postgres \
		-e POSTGRES_PASSWORD=password \
		-e POSTGRES_DB=netvisor \
		-p 5432:5432 \
		postgres:17-alpine || echo "Already running"
	@sleep 3
	@echo "PostgreSQL ready at localhost:5432"

clean-db:
	docker stop netvisor-postgres || true
	docker rm netvisor-postgres || true

clean-daemon:
	rm -rf ~/Library/Application\ Support/com.netvisor.daemon

dump-db:
	docker exec -t netvisor-postgres pg_dump -U postgres -d netvisor > ~/dev/netvisor/netvisor.sql  

dev-server:
	@export DATABASE_URL="postgresql://postgres:password@localhost:5432/netvisor" && \
	cd backend && cargo run --bin server -- --log-level debug --integrated-daemon-url http://localhost:60073

dev-daemon:
	cd backend && cargo run --bin daemon -- --server-target http://127.0.0.1 --server-port 60072 --log-level debug

dev-ui:
	cd ui && npm run dev

dev-container:
	docker compose -f docker-compose.dev.yml up

dev-container-rebuild:
	docker compose -f docker-compose.dev.yml up --build --force-recreate

dev-container-rebuild-clean:
	docker compose -f docker-compose.dev.yml build --no-cache
	docker compose -f docker-compose.dev.yml up

dev-down:
	docker compose -f docker-compose.dev.yml down --volumes --rmi all

build:
	@echo "Building Server + UI Docker image..."
	docker build -f backend/Dockerfile -t mayanayza/netvisor-server:latest .
	@echo "✓ Server image built: mayanayza/netvisor-server:latest"
	@echo ""
	@echo "Building Daemon Docker image..."
	docker build -f backend/Dockerfile.daemon -t mayanayza/netvisor-daemon:latest ./backend
	@echo "✓ Daemon image built: mayanayza/netvisor-daemon:latest"

build-armv7l-docker:
	@echo "Building multi-architecture Docker images using docker buildx..."
	@echo "Checking if docker buildx is available..."
	@docker buildx version > /dev/null || { \
		echo "Docker buildx not found. Installing..."; \
		docker buildx create --use || echo "Warning: Could not set up buildx. Install manually."; \
	}
	@echo ""
	@echo "Building Server + UI for linux/amd64,linux/arm/v7,linux/arm64..."
	docker buildx build -f backend/Dockerfile.multiarch \
		--platform linux/amd64,linux/arm/v7,linux/arm64 \
		-t mayanayza/netvisor-server:latest \
		-t mayanayza/netvisor-server:armv7l \
		--push .
	@echo "✓ Multi-arch server image built and pushed"
	@echo ""
	@echo "Building Daemon for linux/amd64,linux/arm/v7,linux/arm64..."
	docker buildx build -f backend/Dockerfile.daemon.multiarch \
		--platform linux/amd64,linux/arm/v7,linux/arm64 \
		-t mayanayza/netvisor-daemon:latest \
		-t mayanayza/netvisor-daemon:armv7l \
		--push ./backend
	@echo "✓ Multi-arch daemon image built and pushed"
	@echo ""
	@echo "Note: Images were pushed to registry. For local testing, use --load with single platform"

build-armv7l-docker-local:
	@echo "Building local armv7l Docker images (requires docker buildx)..."
	@docker buildx version > /dev/null || { \
		echo "Docker buildx not found. Creating builder..."; \
		docker buildx create --use; \
	}
	@echo ""
	@echo "Building local Server image for armv7l..."
	docker buildx build -f backend/Dockerfile.multiarch \
		--platform linux/arm/v7 \
		-t mayanayza/netvisor-server:armv7l-local \
		--load .
	@echo "✓ Local armv7l server image built"
	@echo ""
	@echo "Building local Daemon image for armv7l..."
	docker buildx build -f backend/Dockerfile.daemon.multiarch \
		--platform linux/arm/v7 \
		-t mayanayza/netvisor-daemon:armv7l-local \
		--load ./backend
	@echo "✓ Local armv7l daemon image built"

test:
	make dev-down
	rm -rf ./data/daemon_config/*
	@export DATABASE_URL="postgresql://postgres:password@localhost:5432/netvisor_test" && \
	cd backend && cargo test -- --nocapture --test-threads=1

format:
	@echo "Formatting Server..."
	cd backend && cargo fmt
	@echo "Formatting UI..."
	cd ui && npm run format
	@echo "All code formatted!"

lint:
	@echo "Linting Server..."
	cd backend && cargo fmt -- --check && cargo clippy --bin server -- -D warnings
	@echo "Linting Daemon..."
	cd backend && cargo clippy --bin daemon -- -D warnings
	@echo "Linting UI..."
	cd ui && npm run lint && npm run format -- --check && npm run check

clean:
	make clean-db
	docker compose down -v
	cd backend && cargo clean
	cd ui && rm -rf node_modules dist build .svelte-kit

install-dev-mac:
	@echo "Installing Rust toolchain..."
	rustup install stable
	rustup component add rustfmt clippy
	@echo "Installing Node.js dependencies..."
	cd ui && npm install
	@echo "Installing pre-commit hooks..."
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "Installing pre-commit via pip..."; \
		pip3 install pre-commit --break-system-packages || pip3 install pre-commit; \
	}
	pre-commit install
	pre-commit install --hook-type pre-push
	@echo "Development dependencies installed!"
	@echo "Note: Run 'source ~/.zshrc' to update your PATH, or restart your terminal"

install-dev-linux:
	@echo "Installing Rust toolchain..."
	rustup install stable
	rustup component add rustfmt clippy
	@echo "Installing Node.js dependencies..."
	cd ui && npm install
	@echo "Installing pre-commit hooks..."
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "Installing pre-commit via pip..."; \
		pip3 install pre-commit --break-system-packages || pip3 install pre-commit; \
	}
	pre-commit install
	pre-commit install --hook-type pre-push
	@echo ""
	@echo "Development dependencies installed!"

install-dev-linux-armv7l:
	@echo "Installing armv7l cross-compilation dependencies on Linux..."
	@echo "Installing Rust toolchain with armv7l target..."
	rustup install stable
	rustup target add armv7-unknown-linux-gnueabihf aarch64-unknown-linux-gnu
	rustup component add rustfmt clippy
	@echo "Installing cross-compilation tools..."
	@which arm-linux-gnueabihf-gcc > /dev/null || { \
		echo "Installing ARM cross-compilation toolchain..."; \
		sudo apt-get update && \
		sudo apt-get install -y build-essential pkg-config libssl-dev \
			gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \
			libc6-dev-armhf-cross linux-libc-dev-armhf-cross || \
		echo "Warning: Could not install ARM toolchain. Install manually with: sudo apt install gcc-arm-linux-gnueabihf"; \
	}
	@echo "Installing Node.js dependencies..."
	cd ui && npm install
	@echo "armv7l cross-compilation setup complete!"
	@echo "Run 'make build-armv7l-server' or 'make build-armv7l-daemon' to compile"

build-armv7l-server:
	@echo "Building Server for armv7l..."
	cd backend && cargo build --release --bin server --target armv7-unknown-linux-gnueabihf
	@echo "✓ Server built for armv7l: backend/target/armv7-unknown-linux-gnueabihf/release/server"

build-armv7l-daemon:
	@echo "Building Daemon for armv7l..."
	cd backend && cargo build --release --bin daemon --target armv7-unknown-linux-gnueabihf
	@echo "✓ Daemon built for armv7l: backend/target/armv7-unknown-linux-gnueabihf/release/daemon"

build-armv7l-daemon-static:
	@echo "Building Daemon for armv7l (static)..."
	cd backend && RUSTFLAGS='-C target-feature=+crt-static' cargo build --release --bin daemon --target armv7-unknown-linux-gnueabihf
	@echo "✓ Static daemon built for armv7l: backend/target/armv7-unknown-linux-gnueabihf/release/daemon"

build-armv7l: build-armv7l-server build-armv7l-daemon
	@echo "✓ All armv7l binaries built successfully"

test-armv7l:
	@echo "Note: Full armv7l tests require actual armv7l hardware or QEMU emulation"
	@echo "Cross-compiled binaries can be tested with: file backend/target/armv7-unknown-linux-gnueabihf/release/server"
	@file backend/target/armv7-unknown-linux-gnueabihf/release/server || echo "Server binary not yet built"
	@file backend/target/armv7-unknown-linux-gnueabihf/release/daemon || echo "Daemon binary not yet built"
