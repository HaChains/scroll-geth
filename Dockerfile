# Support setting various labels on the final image
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

# Build libzkp dependency
FROM scrolltech/go-rust-builder:go-1.20-rust-nightly-2022-12-10 as chef
WORKDIR app

FROM chef as planner
COPY ./rollup/circuitcapacitychecker/libzkp/ .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef as zkp-builder
COPY ./rollup/circuitcapacitychecker/libzkp/rust-toolchain ./
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

COPY ./rollup/circuitcapacitychecker/libzkp .
RUN cargo clean
RUN cargo build --release
RUN find ./ | grep libzktrie.so | xargs -I{} cp {} /app/target/release/

# Build Geth in a stock Go builder container
FROM scrolltech/go-rust-builder:go-1.20-rust-nightly-2022-12-10 as builder

ADD . /go-ethereum
COPY --from=zkp-builder /app/target/release/libzkp.so /usr/local/lib/
COPY --from=zkp-builder /app/target/release/libzktrie.so /usr/local/lib/
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/

RUN mkdir /opt/lib
RUN wget -O /opt/lib/libzktrie.so https://github.com/scroll-tech/da-codec/releases/download/v0.0.0-rc0-ubuntu20.04/libzktrie.so
RUN wget -O /opt/lib/libscroll_zstd.so https://github.com/scroll-tech/da-codec/releases/download/v0.0.0-rc0-ubuntu20.04/libscroll_zstd.so
ENV LD_LIBRARY_PATH=/opt/lib
ENV CGO_LDFLAGS="-L/opt/lib -Wl,-rpath=/opt/lib"
RUN cd /go-ethereum && env GO111MODULE=on go run build/ci.go install -buildtags circuit_capacity_checker ./cmd/geth

# Pull Geth into a second stage deploy alpine container
FROM ubuntu:20.04

RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends ca-certificates wget

COPY --from=builder /go-ethereum/build/bin/geth /usr/local/bin/
COPY --from=zkp-builder /app/target/release/libzkp.so /usr/local/lib/
COPY --from=zkp-builder /app/target/release/libzktrie.so /usr/local/lib/
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/

RUN mkdir /opt/lib
RUN wget -O /opt/lib/libzktrie.so https://github.com/scroll-tech/da-codec/releases/download/v0.0.0-rc0-ubuntu20.04/libzktrie.so
RUN wget -O /opt/lib/libscroll_zstd.so https://github.com/scroll-tech/da-codec/releases/download/v0.0.0-rc0-ubuntu20.04/libscroll_zstd.so
ENV LD_LIBRARY_PATH=/opt/lib
ENV CGO_LDFLAGS="-L/opt/lib -Wl,-rpath=/opt/lib"

EXPOSE 8545 8546 30303 30303/udp
ENTRYPOINT ["geth"]

# Add some metadata labels to help programatic image consumption
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

LABEL commit="$COMMIT" version="$VERSION" buildnum="$BUILDNUM"
