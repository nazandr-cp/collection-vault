FROM ghcr.io/foundry-rs/foundry:v1.2.3

WORKDIR /app
COPY . .

RUN forge --version && forge soldeer install && forge build src

CMD ["anvil", "-p", "8545", "--host", "0.0.0.0"]
