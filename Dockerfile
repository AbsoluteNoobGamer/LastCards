# ── Build stage ───────────────────────────────────────────────────────────────
# The base image's own `dart` binary is never used — Flutter installs its own
# bundled Dart SDK below and /opt/flutter/bin is prepended to PATH before any
# `dart`/`flutter pub get` command runs, so what actually matters is the
# FLUTTER_VERSION pinned below, not this tag. Kept on a dart: image purely for
# a small Debian base with apt available.
FROM dart:3.9.2 AS build

# Install Flutter SDK (same version the app targets)
RUN apt-get update -q && apt-get install -y --no-install-recommends \
      curl git unzip xz-utils ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Must satisfy in_app_purchase 3.3.0's own constraint (sdk: ^3.10.0,
# flutter: >=3.38.0) — a transitive dep pulled in via the root last_cards
# package. Bundled Dart SDK for 3.41.9 is 3.11.5.
ENV FLUTTER_VERSION=3.41.9
RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz && \
    tar -xf /tmp/flutter.tar.xz -C /opt && \
    rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:${PATH}"

RUN git config --global --add safe.directory /opt/flutter

# Pre-cache Flutter tool (suppresses first-run setup during pub get)
RUN flutter precache --no-android --no-ios --no-web --no-fuchsia

WORKDIR /app

# Copy the entire repo (server depends on root package via path: ..)
COPY . .

# Resolve server dependencies using flutter pub (needed for the path dep on
# last_cards which is a Flutter package), then compile with dart.
RUN cd server && flutter pub get
RUN cd server && dart compile exe bin/main.dart -o bin/server

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

COPY --from=build /app/server/bin/server /server

EXPOSE 8080
CMD ["/server"]
