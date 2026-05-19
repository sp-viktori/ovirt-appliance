# Use %{rhel} which is set by *-release packages on CentOS Stream, AlmaLinux,
# and Oracle Linux alike (centos_ver isn't set on Oracle Linux).
if [[ $(rpm --eval '%{rhel}') == '9' ]]; then
    # --force: overwrites kiwi's pre-staged /etc/pam.d/* during build
    authselect select minimal --force
else
    authselect select local --force
fi

systemctl enable firewalld
systemctl enable sshd
systemctl enable fstrim.timer
systemctl enable cockpit.socket
systemctl enable qemu-guest-agent
firewall-offline-cmd --add-service=cockpit

if [[ "$kiwi_profiles" == *"cbs-testing"* ]]; then
    # Enable oVirt Testing Repository
    dnf config-manager --set-enabled centos-ovirt45-testing
    dnf config-manager --set-enabled ovirt-45-upstream-testing
fi

# Oracle Linux 9 chroot setup: kiwi-level repos don't propagate to
# /etc/yum.repos.d/ inside the built chroot, so anchor what's needed here.
# CRB has apache-commons-* and jakarta-servlet (provides javax.servlet-api).
# EPEL covers a few smaller deps. @OLVM_CACHE_URL@ is sed-substituted by
# olvm/build/build-appliance.sh before kiwi runs; the same URL is baked
# into the deployed appliance, so set OLVM_CACHE_URL to a host the demo
# engine VM can reach.
if [[ "$kiwi_profiles" == *"oraclelinux"* ]]; then
    dnf -y install epel-release || true
    dnf config-manager --enable ol9_codeready_builder
    cat > /etc/yum.repos.d/olvm-storpool.repo <<'EOF'
[olvm-storpool]
name=OLVM StorPool patched engine
baseurl=@OLVM_CACHE_URL@/ol9/
gpgcheck=0
enabled=1
EOF
fi

# Install oVirt Packages
dnf -y install ovirt-engine \
            ovirt-engine-dwh \
            ovirt-provider-ovn \
            ovirt-engine-extension-aaa-ldap \
            ovirt-engine-extension-aaa-ldap-setup \
            ovirt-engine-extension-aaa-misc

# The openjdk %post update-alternatives doesn't materialize inside the
# kiwi chroot, so /usr/bin/keytool is absent and engine-setup dies at the
# Misc configuration stage. Pin it to the java-17 keytool explicitly.
kt=$(ls -1 /usr/lib/jvm/java-17-openjdk-*/bin/keytool 2>/dev/null | head -1)
if [[ -n "$kt" ]]; then
    ln -sf "$kt" /usr/bin/keytool
else
    echo "WARNING: java-17 keytool not found; engine-setup will fail" >&2
fi

# StorPool managed-block adapter wiring. python3-sp-ovirt ships
# /usr/bin/sp-ovirt-adapter; ovirt-engine looks for the adapter under
# /usr/share/ovirt-engine/managedblock/.
mkdir -p /usr/share/ovirt-engine/managedblock
ln -sf /usr/bin/sp-ovirt-adapter /usr/share/ovirt-engine/managedblock/storpool-adapter