FROM ghcr.io/foundry-rs/foundry:latest

WORKDIR /app
COPY . .

RUN forge --version && forge soldeer install && forge build

CMD ["anvil", "-p", "8545", "--host", "0.0.0.0"]
