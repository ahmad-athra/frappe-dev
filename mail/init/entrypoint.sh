#!/bin/sh
# =============================================================================
# mail-init — declarative, idempotent provisioning of the Stalwart mail server
# Feature: F-006 Self-Hosted Email (context/features/F-006-self-hosted-email)
#
# Converges the server towards the state described by environment variables:
#   * logging tracer -> stdout (default file tracer targets a missing directory)
#   * mail domain + system default hostname
#   * mailbox accounts (MAIL_ACCOUNTS)
#   * outbound routing strategy (MAIL_OUTBOUND_ROUTE: mailpit | mx | relay)
#   * TLS (MAIL_TLS_MODE): dev-ca -> local CA + leaf cert served by Stalwart and a trust
#     bundle published for clients; external -> certificates managed outside (ACME/manual)
# then reloads settings. Safe to re-run at any time (every op is upsert/update/reconcile).
#
# Secrets are read from env only, JSON-encoded with jq and streamed to the CLI
# over stdin; they are never written to disk or echoed.
# =============================================================================
set -eu

# ---- Required / defaulted inputs -------------------------------------------
: "${STALWART_URL:=http://mail:8080}"
: "${STALWART_USER:=admin}"
: "${STALWART_PASSWORD:?STALWART_PASSWORD (MAIL_ADMIN_PASSWORD) is required}"
: "${MAIL_DOMAIN:?MAIL_DOMAIN is required}"
: "${MAIL_HOSTNAME:=mail.${MAIL_DOMAIN}}"
: "${MAIL_ACCOUNTS:=}"
: "${MAIL_OUTBOUND_ROUTE:=mx}"
: "${MAILPIT_HOST:=mailpit}"
: "${MAILPIT_SMTP_PORT:=1025}"
: "${MAIL_READY_TIMEOUT_SEC:=120}"
: "${MAIL_TLS_MODE:=external}"
: "${MAIL_TLS_EXTRA_SANS:=}"
: "${MAIL_PKI_DIR:=/pki}"
: "${MAIL_TRUST_DIR:=/trust}"
: "${MAIL_SPAM_FILTER:=enabled}"
export STALWART_URL STALWART_USER STALWART_PASSWORD

# ---- Structured JSON logging -------------------------------------------------
log() {
	jq -cn --arg level "$1" --arg msg "$2" --arg domain "$MAIL_DOMAIN" \
		'{timestamp: (now | todate), service: "mail-init", level: $level, mail_domain: $domain, message: $msg}'
}

fail() {
	log error "$1" >&2
	exit 1
}

# ---- Wait for the server -----------------------------------------------------
wait_ready() {
	elapsed=0
	until curl -fsS -o /dev/null -H "X-Forwarded-For: 127.0.0.1" "${STALWART_URL}/healthz/ready"; do
		elapsed=$((elapsed + 2))
		[ "$elapsed" -ge "$MAIL_READY_TIMEOUT_SEC" ] && fail "Stalwart not ready after ${MAIL_READY_TIMEOUT_SEC}s at ${STALWART_URL}"
		sleep 2
	done
	log info "Stalwart is ready"
}

# ---- Dev PKI (MAIL_TLS_MODE=dev-ca) -----------------------------------------
# CA key never leaves MAIL_PKI_DIR (private volume). Clients only receive the public
# trust bundle in MAIL_TRUST_DIR. Certificates satisfy Python 3.13+ VERIFY_X509_STRICT
# (critical basicConstraints, keyUsage, SKI/AKI) used by ssl.create_default_context().
CA_KEY="${MAIL_PKI_DIR}/ca.key"
CA_CRT="${MAIL_PKI_DIR}/ca.crt"
LEAF_KEY="${MAIL_PKI_DIR}/leaf.key"
LEAF_CRT="${MAIL_PKI_DIR}/leaf.crt"
LEAF_SANS_FILE="${MAIL_PKI_DIR}/leaf.sans"
RENEW_BEFORE_SEC=2592000 # 30 days

ensure_dev_pki() {
	sans="DNS:mail,DNS:${MAIL_HOSTNAME},DNS:localhost,IP:127.0.0.1"
	[ -n "$MAIL_TLS_EXTRA_SANS" ] && sans="${sans},${MAIL_TLS_EXTRA_SANS}"

	old_umask=$(umask)
	umask 077
	if [ ! -s "$CA_KEY" ] || [ ! -s "$CA_CRT" ]; then
		openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
			-subj "/CN=Enterprise Hub Dev Mail CA" -keyout "$CA_KEY" -out "$CA_CRT" \
			-addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
			-addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null \
			|| fail "Failed to create dev CA"
		log info "Created dev mail CA"
	fi

	if [ ! -s "$LEAF_CRT" ] || [ "$(cat "$LEAF_SANS_FILE" 2>/dev/null)" != "$sans" ] \
		|| ! openssl x509 -checkend "$RENEW_BEFORE_SEC" -noout -in "$LEAF_CRT" >/dev/null 2>&1; then
		ext="${MAIL_PKI_DIR}/leaf.ext"
		printf '%s\n' \
			"basicConstraints=critical,CA:FALSE" \
			"keyUsage=critical,digitalSignature" \
			"extendedKeyUsage=serverAuth" \
			"subjectKeyIdentifier=hash" \
			"authorityKeyIdentifier=keyid:always" \
			"subjectAltName=${sans}" >"$ext"
		openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
			-subj "/CN=${MAIL_HOSTNAME}" -keyout "$LEAF_KEY" -out "${MAIL_PKI_DIR}/leaf.csr" 2>/dev/null \
			|| fail "Failed to create leaf key/CSR"
		openssl x509 -req -in "${MAIL_PKI_DIR}/leaf.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" \
			-CAcreateserial -days 397 -extfile "$ext" -out "$LEAF_CRT" 2>/dev/null \
			|| fail "Failed to issue leaf certificate"
		printf '%s' "$sans" >"$LEAF_SANS_FILE"
		log info "Issued mail TLS certificate (${sans})"
	fi
	umask "$old_umask"

	# Public trust material: system roots + dev CA (atomic replace, world-readable).
	cat /etc/ssl/certs/ca-certificates.crt "$CA_CRT" >"${MAIL_TRUST_DIR}/ca-bundle.pem.tmp"
	mv "${MAIL_TRUST_DIR}/ca-bundle.pem.tmp" "${MAIL_TRUST_DIR}/ca-bundle.pem"
	cp "$CA_CRT" "${MAIL_TRUST_DIR}/dev-mail-ca.crt"
	chmod 0644 "${MAIL_TRUST_DIR}/ca-bundle.pem" "${MAIL_TRUST_DIR}/dev-mail-ca.crt"
}

op_certificate() {
	[ "$MAIL_TLS_MODE" = "dev-ca" ] || return 0
	# Full chain (leaf + CA) so clients can build the path from the bundle.
	jq -cn --rawfile crt "$LEAF_CRT" --rawfile ca "$CA_CRT" --rawfile key "$LEAF_KEY" \
		'{"@type":"reconcile", object:"Certificate", matchOn:["certificate"],
			value:{cert:{certificate:{"@type":"Text", value:($crt + $ca)},
				privateKey:{"@type":"Text", secret:$key}}}}'
	jq -cn '{"@type":"update", object:"SystemSettings", value:{defaultCertificateId:"#cert"}}'
}

# ---- Plan builders (one NDJSON operation per line) ---------------------------
op_tracer() {
	jq -cn '{"@type":"reconcile", object:"Tracer", matchOn:"*",
		value:{t:{"@type":"Stdout", enable:true, level:"info"}}}'
}

op_domain() {
	jq -cn --arg name "$MAIL_DOMAIN" '{"@type":"upsert", object:"Domain", matchOn:["name"],
		value:{dom:{name:$name}}}'
}

op_system_settings() {
	jq -cn --arg host "$MAIL_HOSTNAME" '{"@type":"update", object:"SystemSettings",
		value:{defaultDomainId:"#dom", defaultHostname:$host}}'
}

# MAIL_ACCOUNTS="localpart:SECRET_ENV_VAR[,localpart:SECRET_ENV_VAR...]"
op_accounts() {
	[ -n "$MAIL_ACCOUNTS" ] || return 0
	index=0
	old_ifs=$IFS
	IFS=','
	for entry in $MAIL_ACCOUNTS; do
		IFS=$old_ifs
		local_part=${entry%%:*}
		secret_var=${entry#*:}
		case "$local_part" in
			'' | *[!a-z0-9._-]*) fail "Invalid account local part in MAIL_ACCOUNTS: '${local_part}'" ;;
		esac
		case "$secret_var" in
			'' | [0-9]* | *[!A-Za-z0-9_]*) fail "Invalid secret variable name for account '${local_part}'" ;;
		esac
		secret=$(printenv "$secret_var" || true)
		[ -n "$secret" ] || fail "Secret ${secret_var} for account '${local_part}' is empty or unset"

		index=$((index + 1))
		jq -cn --arg ref "acc${index}" --arg name "$local_part" --arg secret "$secret" \
			--arg desc "Provisioned by mail-init (F-006)" \
			'{"@type":"upsert", object:"Account", matchOn:["name","domainId"],
				value:{($ref):{"@type":"User", name:$name, domainId:"#dom", description:$desc,
					credentials:{"0":{"@type":"Password", secret:$secret}}}}}'
		IFS=','
	done
	IFS=$old_ifs
}

# Stalwart expressions take string literals in single quotes, e.g. 'local'.
op_strategy() {
	jq -cn --arg local "'local'" --arg target "'$1'" '{"@type":"update", object:"MtaOutboundStrategy",
		value:{route:{match:{"0":{if:"is_local_domain(rcpt_domain)", then:$local}}, else:$target}}}'
}

op_routing() {
	case "$MAIL_OUTBOUND_ROUTE" in
		mailpit)
			jq -cn --arg host "$MAILPIT_HOST" --argjson port "$MAILPIT_SMTP_PORT" \
				'{"@type":"upsert", object:"MtaRoute", matchOn:["name"],
					value:{r:{"@type":"Relay", name:"mailpit", description:"Dev mail catcher (F-006)",
						address:$host, port:$port, protocol:"smtp", implicitTls:false, allowInvalidCerts:true,
						authSecret:{"@type":"None"}}}}'
			op_strategy mailpit
			;;
		relay)
			: "${MAIL_RELAY_HOST:?MAIL_RELAY_HOST is required when MAIL_OUTBOUND_ROUTE=relay}"
			: "${MAIL_RELAY_PORT:=587}"
			: "${MAIL_RELAY_IMPLICIT_TLS:=false}"
			: "${MAIL_RELAY_USER:=}"
			# The relay password is resolved by Stalwart itself from ITS environment
			# (variable MAIL_RELAY_PASSWORD on the `mail` service) — it never enters the plan.
			jq -cn --arg host "$MAIL_RELAY_HOST" --argjson port "$MAIL_RELAY_PORT" \
				--argjson tls "$MAIL_RELAY_IMPLICIT_TLS" --arg user "$MAIL_RELAY_USER" \
				'{"@type":"upsert", object:"MtaRoute", matchOn:["name"],
					value:{r:({"@type":"Relay", name:"smarthost", description:"Outbound smarthost (F-006)",
						address:$host, port:$port, protocol:"smtp", implicitTls:$tls, allowInvalidCerts:false}
						+ (if $user == "" then {authSecret:{"@type":"None"}}
						   else {authUsername:$user,
						         authSecret:{"@type":"EnvironmentVariable", variableName:"MAIL_RELAY_PASSWORD"}} end))}}'
			op_strategy smarthost
			;;
		mx)
			op_strategy mx
			;;
		*)
			fail "Unsupported MAIL_OUTBOUND_ROUTE '${MAIL_OUTBOUND_ROUTE}' (expected mailpit|mx|relay)"
			;;
	esac
}

op_spam() {
	case "$MAIL_SPAM_FILTER" in
		enabled) enable=true ;;
		disabled) enable=false ;;
		*) fail "Unsupported MAIL_SPAM_FILTER '${MAIL_SPAM_FILTER}' (expected enabled|disabled)" ;;
	esac
	# Dev mail has no SPF/DKIM/DNS and would be classified as Junk (never reaching INBOX).
	jq -cn --argjson enable "$enable" '{"@type":"update", object:"SpamSettings", value:{enable:$enable}}'
}

op_reload() {
	jq -cn '{"@type":"create", object:"Action", value:{a:{"@type":"ReloadSettings"}}}'
	if [ "$MAIL_TLS_MODE" = "dev-ca" ]; then
		jq -cn '{"@type":"create", object:"Action", value:{b:{"@type":"ReloadTlsCertificates"}}}'
	fi
}

apply_plan() {
	stalwart-cli --no-color apply --stdin --quiet
}

# ---- Main --------------------------------------------------------------------
main() {
	log info "Provisioning started (route=${MAIL_OUTBOUND_ROUTE}, tls=${MAIL_TLS_MODE}, hostname=${MAIL_HOSTNAME})"
	case "$MAIL_TLS_MODE" in
		dev-ca) ensure_dev_pki ;;
		external) ;;
		*) fail "Unsupported MAIL_TLS_MODE '${MAIL_TLS_MODE}' (expected dev-ca|external)" ;;
	esac
	wait_ready

	# Build the full plan first so validation errors abort before any server call.
	plan=$(
		op_tracer
		op_domain
		op_system_settings
		op_certificate
		op_accounts
		op_routing
		op_spam
	)

	printf '%s\n' "$plan" | apply_plan || fail "Plan apply failed"
	op_reload | apply_plan || fail "ReloadSettings failed"

	log info "Provisioning completed"
}

main "$@"
