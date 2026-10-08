# syntax=docker/dockerfile:1
# etcd, the store Patroni keeps the database's leader lease in: the upstream image at a pinned
# release and digest, native on every core. Moving to a new version is this one line, deployed a
# member at a time. See spec/architecture/databases.md, "Where it runs, and which one writes".
FROM gcr.io/etcd-development/etcd:v3.7.2@sha256:7c6c239825d00e3f6328a69caafd54be92063acf0c2ce78b8394699f52b75dc3
# Heartbeat and election for three continents, its farthest pair 380 ms apart. Clients on 2379 by
# password (`database quorum-auth`); peers on 2380 by certificates of the members' own CA, which
# `database env` writes to /data/tls; health on the container's own port; name and addresses are
# each node's. Quota and compaction are Pigsty v4.5.0's, roles/etcd/templates/etcd.conf: without
# compaction Patroni's every write grows a history the quota then stops.
ENV ETCD_DATA_DIR=/data/etcd \
	ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379 \
	ETCD_LISTEN_PEER_URLS=https://0.0.0.0:2380 \
	ETCD_LISTEN_METRICS_URLS=http://0.0.0.0:23790 \
	ETCD_PEER_CERT_FILE=/data/tls/peer.crt \
	ETCD_PEER_KEY_FILE=/data/tls/peer.key \
	ETCD_PEER_TRUSTED_CA_FILE=/data/tls/ca.crt \
	ETCD_PEER_CLIENT_CERT_AUTH=true \
	ETCD_HEARTBEAT_INTERVAL=500 \
	ETCD_ELECTION_TIMEOUT=5000 \
	ETCD_QUOTA_BACKEND_BYTES=8589934592 \
	ETCD_AUTO_COMPACTION_MODE=periodic \
	ETCD_AUTO_COMPACTION_RETENTION=24h \
	ETCD_INITIAL_CLUSTER_STATE=new \
	ETCD_INITIAL_CLUSTER_TOKEN=platform-quorum
# The upstream image runs as root; a member runs as nobody in particular, by number, and host
# gives the app's directory to this user.
USER 65532:65532
