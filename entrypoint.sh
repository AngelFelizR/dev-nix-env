#!/bin/sh
# Bootstraps the dev sshd and execs it. The nixos/nix base has no sshd/dev
# user (/etc/passwd is a read-only symlink into the store), so the privsep
# account and the login user `dev` are added here to writable copies; host
# keys are generated on first start.
set -eu

if ! grep -q '^sshd:' /etc/passwd 2>/dev/null; then
    cp -L /etc/passwd  /tmp/passwd.bak
    cp -L /etc/group   /tmp/group.bak
    cp -L /etc/shadow  /tmp/shadow.bak
    rm -f /etc/passwd /etc/group /etc/shadow
    cat /tmp/passwd.bak > /etc/passwd
    cat /tmp/group.bak  > /etc/group
    # Unlock root: sshd refuses pubkey logins while the shadow field starts
    # with "!"; "*" keeps password login impossible but allows the key.
    while IFS= read -r line; do
        case "$line" in
            root:*) printf 'root:*:%s\n' "${line#root:*:}" ;;
            *)      printf '%s\n' "$line" ;;
        esac
    done < /tmp/shadow.bak > /etc/shadow
    echo 'sshd:x:65532:65532:Privilege separation user:/var/empty:/sbin/nologin' >> /etc/passwd
    echo 'sshd:x:65532:' >> /etc/group
    # Login user (uid 1000 = host user): SSH sessions run as `dev` so files
    # written in the mounted repo are owned by the host user, not root.
    # Nix store writes stay root-only; adding packages is done as root
    # (see README: "docker compose exec -u root ... nix-shell").
    echo 'dev:x:1000:1000::/home/dev:/bin/sh' >> /etc/passwd
    echo 'dev:x:1000:' >> /etc/group
    rm -f /tmp/passwd.bak /tmp/group.bak /tmp/shadow.bak
fi

mkdir -p /var/empty /run/sshd /home/dev/.ssh /etc/ssh
chmod 700 /var/empty /home/dev/.ssh
# Owned by the dev user; already set at build time, ensured here in case the
# home dir was created fresh. Non-recursive: don't chown the mounted repo.
chown 1000:1000 /home/dev /home/dev/.ssh 2>/dev/null || true

[ -f /etc/ssh/ssh_host_ed25519_key ] || \
    /opt/system/bin/ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key

cat > /etc/ssh/sshd_config <<'EOF'
Port 22
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile .ssh/authorized_keys
# The image ENV (R_LIBS_SITE, locales, fonts) never reaches an ssh session;
# ~/.ssh/environment carries it instead.
PermitUserEnvironment yes
UsePAM no
PrintMotd no
PidFile /run/sshd.pid
EOF

exec /opt/system/bin/sshd -D -e -f /etc/ssh/sshd_config
