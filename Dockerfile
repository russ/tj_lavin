FROM crystallang/crystal:1.17.0

WORKDIR /app

COPY shard.yml shard.lock ./
RUN shards install --skip-postinstall --skip-executables

COPY . .
