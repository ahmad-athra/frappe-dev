# One-shot provisioner for the Stalwart mail server (feature F-006).
# The official CLI image is distroless (no shell), so the binary is copied onto Alpine
# together with jq (safe JSON encoding of secrets), curl (readiness probe) and openssl (dev CA).
FROM stalwartlabs/cli:1.0.13 AS cli

FROM alpine:3.22
RUN apk add --no-cache ca-certificates curl jq openssl
COPY --from=cli /usr/local/bin/stalwart-cli /usr/local/bin/stalwart-cli
COPY entrypoint.sh /usr/local/bin/mail-init
# /pki (private: CA + leaf keys) and /trust (public: CA bundle) are volume mount points. Docker
# seeds empty named volumes with the image directory's ownership/mode, so the unprivileged
# user can write to them.
RUN sed -i 's/\r$//' /usr/local/bin/mail-init \
	&& chmod 0755 /usr/local/bin/mail-init \
	&& stalwart-cli --version \
	&& adduser -D -h /home/mailinit mailinit \
	&& install -d -o mailinit -g mailinit -m 0700 /pki \
	&& install -d -o mailinit -g mailinit -m 0755 /trust

# The CLI writes state under $HOME, so the unprivileged user needs a real home directory.
USER mailinit
WORKDIR /home/mailinit
ENTRYPOINT ["/usr/local/bin/mail-init"]
