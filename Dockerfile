# ── Build stage ───────────────────────────────────────────────────────────────
# Use Dart 3.11.2 (satisfies google_fonts ^8.0.2 which needs Dart >=3.9.0).
# We also install Flutter so that `flutter pub get` can resolve the root
# package (last_cards) which declares `flutter: sdk: flutter`.
FROM dart:3.11.2 AS build

# Install Flutter SDK (same version the app targets)
RUN apt-get update -q && apt-get install -y --no-install-recommends \
      curl git unzip xz-utils ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV FLUTTER_VERSION=3.29.2
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
