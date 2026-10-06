import Foundation

enum DockerfileTemplates {

    // MARK: - Dockerfile

    static func dockerfile(appName: String) -> String {
        return """
        # Build stage
        FROM swift:6.3.3-noble AS build
        RUN apt-get update && apt-get install -y --no-install-recommends zlib1g-dev && \\
            rm -rf /var/lib/apt/lists/*
        WORKDIR /app
        COPY Package.* ./
        RUN swift package resolve
        COPY . .
        RUN swift build -c release --product \(appName) && \\
            mkdir -p /release/Public /release/Sources/Migrations && \\
            cp "$(swift build -c release --show-bin-path)/\(appName)" /release/app && \\
            cp -a Public/. /release/Public/ && \\
            if [ -d Sources/Migrations ]; then cp -a Sources/Migrations/. /release/Sources/Migrations/; fi

        # Runtime stage
        FROM swift:6.3.3-noble-slim
        RUN apt-get update && apt-get install -y --no-install-recommends zlib1g && \\
            rm -rf /var/lib/apt/lists/*
        WORKDIR /app
        COPY --from=build /release/ /app/
        EXPOSE 8080
        ENV ROOST_HOST=0.0.0.0
        ENV ROOST_PORT=8080
        ENV ROOST_ENV=prod
        ENTRYPOINT ["/app/app"]
        """
    }

    // MARK: - .dockerignore

    static func dockerignore() -> String {
        return """
        .build/
        .swiftpm/
        .git/
        *.xcodeproj
        DerivedData/
        """
    }
}
