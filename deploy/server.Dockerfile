# Game server image: the exported Linux dedicated server (build/server, made by CI or
# `godot --headless --export-release "Linux Server" build/server/cradle_server.x86_64`)
# plus the entrypoint that turns stop signals into a graceful, saving shutdown.
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 cradle
WORKDIR /srv/cradle
COPY build/server/ ./
COPY tools/server_entrypoint.sh ./server_entrypoint.sh
RUN chmod +x cradle_server.x86_64 server_entrypoint.sh && chown -R cradle /srv/cradle
USER cradle
EXPOSE 7777/udp
ENTRYPOINT ["./server_entrypoint.sh", "./cradle_server.x86_64", "--headless", "--"]
CMD ["--server", "--port=7777"]
