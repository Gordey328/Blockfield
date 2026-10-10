FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 libx11-6 libxcursor1 libxinerama1 libgl1 libxi6 libxrandr2 libasound2 libpulse0 libudev1 && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/blockfield
COPY build/server/ ./
RUN chmod 0755 blockfield.x86_64 && mkdir -p /home/blockfield && chown 10001:10001 /home/blockfield
ENV HOME=/home/blockfield
USER 10001:10001
EXPOSE 8765 8766
ENTRYPOINT ["./blockfield.x86_64", "--headless"]
CMD ["--", "--server", "--bind=0.0.0.0", "--game-port=8765", "--map-port=8766", "--mode=ctf", "--profile=0.75"]
