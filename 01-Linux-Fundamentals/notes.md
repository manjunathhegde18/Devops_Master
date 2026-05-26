# Linux Fundamentals — Deep Dive Notes

## 1. File System Hierarchy

```
/           Root
├── bin     Essential binaries (ls, cp, mv)
├── sbin    System binaries (root-only)
├── etc     Configuration files
├── var     Variable data (logs, spools)
├── tmp     Temporary files (cleared on boot)
├── home    User home directories
├── root    Root user home
├── proc    Virtual FS — kernel/process info
├── sys     Virtual FS — hardware/kernel params
├── dev     Device files
├── lib     Shared libraries
├── usr     User programs, libraries, docs
├── opt     Optional/third-party software
├── mnt     Mount points
├── media   Removable media
└── boot    Bootloader, kernel images
```

## 2. File Permissions & ACLs

### Basic Permissions
```bash
# Format: [type][owner][group][others]
# -rwxr-xr--  1 alice devops 4096 Jan 1 12:00 script.sh
#  ^   ^  ^  ^
#  |   |  |  other: r--
#  |   |  group: r-x
#  |   owner: rwx
#  type: - (file), d (dir), l (symlink), b (block), c (char)

chmod 755 script.sh       # symbolic mode
chmod u+x,g-w file        # relative
chown alice:devops file   # change owner
```

### Special Bits
- **SUID (4):** Runs as file owner — `chmod u+s binary` → `-rwsr-xr-x`
- **SGID (2):** Runs as file group / new files inherit group
- **Sticky (1):** Only owner can delete — used on `/tmp` → `drwxrwxrwt`

### ACLs (Access Control Lists)
```bash
getfacl file.txt
setfacl -m u:bob:rwx file.txt      # add ACL for user bob
setfacl -m g:devops:r-- dir/       # group ACL
setfacl -x u:bob file.txt          # remove ACL
setfacl -d -m u:bob:rwx dir/       # default ACL (inherited by new files)
```

## 3. Process Management

### Signals
| Signal | Number | Description |
|--------|--------|-------------|
| SIGTERM | 15 | Graceful shutdown request |
| SIGKILL | 9 | Force kill (cannot be caught) |
| SIGHUP | 1 | Reload config / terminal hangup |
| SIGINT | 2 | Interrupt (Ctrl+C) |
| SIGSTOP | 19 | Pause process (cannot be caught) |
| SIGCONT | 18 | Resume paused process |

```bash
kill -15 PID          # graceful
kill -9 PID           # force
pkill -f "python app" # by name pattern
killall nginx
```

### Process States
- **R** — Running/Runnable
- **S** — Interruptible sleep (waiting for event)
- **D** — Uninterruptible sleep (I/O wait) — bad if persistent
- **Z** — Zombie (parent hasn't called wait())
- **T** — Stopped (SIGSTOP)

### Systemd
```bash
systemctl start|stop|restart|reload nginx
systemctl enable|disable nginx        # boot persistence
systemctl status nginx
journalctl -u nginx -f               # follow logs
journalctl --since "1 hour ago"
systemctl list-units --type=service --state=running

# Create a service unit
cat /etc/systemd/system/myapp.service
[Unit]
Description=My App
After=network.target

[Service]
ExecStart=/usr/bin/myapp
Restart=always
User=myapp
EnvironmentFile=/etc/myapp/env

[Install]
WantedBy=multi-user.target
```

## 4. Kernel Namespaces & Cgroups (Container Foundation)

### Namespaces (isolation)
| Namespace | Isolates |
|-----------|---------|
| PID | Process IDs |
| NET | Network interfaces, routes |
| MNT | Mount points |
| UTS | Hostname, domain name |
| IPC | System V IPC, POSIX MQ |
| USER | User/group IDs |
| CGROUP | Cgroup root directory |

```bash
# View namespaces
lsns
ls -la /proc/1/ns/

# Enter namespace of a container
nsenter -t $(docker inspect -f '{{.State.Pid}}' container) --net ip addr
```

### Cgroups (resource limits)
```bash
# v2 (modern)
ls /sys/fs/cgroup/
cat /sys/fs/cgroup/memory/docker/CONTAINER_ID/memory.limit_in_bytes

# Manually limit CPU for a process
cgcreate -g cpu:/mygroup
echo 50000 > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_quota_us  # 50% of one core
cgexec -g cpu:mygroup my_command
```

## 5. Shell Scripting — Advanced

### Bash Best Practices
```bash
#!/usr/bin/env bash
set -euo pipefail       # exit on error, undefined vars, pipe failures
IFS=$'\n\t'             # safer word splitting

# Trap for cleanup
cleanup() {
    echo "Cleaning up..."
    rm -f /tmp/lockfile
}
trap cleanup EXIT ERR

# Parameter expansion
VAR=${1:-"default"}     # default value
VAR=${1:?"Error: arg1 required"}  # error if empty
VAR=${MYVAR^^}          # uppercase
VAR=${MYVAR,,}          # lowercase
VAR=${VAR%suffix}       # remove suffix
VAR=${VAR#prefix}       # remove prefix

# Arrays
declare -a arr=("a" "b" "c")
for item in "${arr[@]}"; do echo "$item"; done
echo "Length: ${#arr[@]}"

# Associative arrays
declare -A map
map["key"]="value"
echo "${map["key"]}"

# Here document
cat <<EOF > /tmp/config
server {
    listen 80;
    server_name ${DOMAIN};
}
EOF
```

### Useful Text Processing
```bash
# awk
awk '{print $1, $3}' file           # columns 1 and 3
awk -F: '{print $1}' /etc/passwd    # custom delimiter
awk 'NR==5,NR==10' file             # lines 5-10
awk '/pattern/ {sum+=$2} END {print sum}' file

# sed
sed -i 's/old/new/g' file           # in-place replace
sed -n '10,20p' file                # print lines 10-20
sed '/^#/d' file                    # delete comment lines
sed 's/[[:space:]]*$//' file        # trim trailing whitespace

# grep
grep -r "pattern" /etc/             # recursive
grep -l "pattern" *.conf            # file names only
grep -v "exclude" file              # invert match
grep -P "regex" file                # Perl regex
grep -A 3 -B 2 "match" file        # context lines

# find
find /var/log -name "*.log" -mtime +30 -delete    # old logs
find / -perm /4000 -user root 2>/dev/null          # SUID files
find /app -type f -newer reference.txt             # newer than
```

## 6. Performance Analysis Tools

### CPU
```bash
top / htop
mpstat -P ALL 1          # per-core utilization
vmstat 1 5               # system activity every 1s, 5 times
sar -u 1 10              # CPU via sysstat
perf top                 # real-time perf counter
perf stat command        # measure command
```

### Memory
```bash
free -h
/proc/meminfo
vmstat -s
pmap -x PID              # process memory map
smem -t                  # memory by process (with PSS)
```

### Disk I/O
```bash
iostat -xz 1             # per-device extended stats
iotop                    # per-process I/O
lsof +D /path            # files open in directory
fuser /dev/sda           # who's using device
blkio in cgroups
```

### Network
```bash
ss -tunapl               # all sockets
nethogs                  # per-process bandwidth
iftop -i eth0            # per-connection bandwidth
tcpdump -i eth0 -w cap.pcap 'port 80 and host 10.0.0.1'
tcpdump -r cap.pcap -A   # read capture
```

## 7. Linux Networking

### iptables / nftables
```bash
# iptables
iptables -L -v -n --line-numbers
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -j DROP
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables-save > /etc/iptables/rules.v4

# nftables (modern replacement)
nft list ruleset
nft add rule inet filter input tcp dport 22 accept
```

### Network Troubleshooting
```bash
ip addr show
ip route show
ip link set eth0 up/down
traceroute / tracepath
mtr google.com           # continuous traceroute
dig @8.8.8.8 example.com ANY +trace
nslookup example.com
curl -v --trace-time https://api.example.com
openssl s_client -connect api.example.com:443
```

## 8. Key Configuration Files

```
/etc/fstab              Mount table
/etc/hosts              Static hostname resolution
/etc/resolv.conf        DNS client config
/etc/nsswitch.conf      Name service switch
/etc/sshd_config        SSH server config
/etc/sudoers            Sudo rules (edit with visudo)
/etc/cron.d/            Cron jobs
/etc/logrotate.d/       Log rotation config
/etc/security/limits.conf  ulimit settings
/etc/sysctl.conf        Kernel parameter tuning
```

## 9. Kernel Tuning for Production

```bash
# /etc/sysctl.conf
net.ipv4.ip_forward = 1                  # Enable routing (required for K8s)
net.bridge.bridge-nf-call-iptables = 1   # Required for K8s CNI
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.core.somaxconn = 65535               # Max connection backlog
net.ipv4.ip_local_port_range = 1024 65535
vm.swappiness = 10                       # Minimize swap
vm.overcommit_memory = 1                 # Allow memory overcommit (K8s)
fs.inotify.max_user_watches = 524288     # Required for many tools

sysctl -p      # apply changes
```

## 10. Key Linux Commands Quick Reference

```bash
# System info
uname -a; hostnamectl; lscpu; lsmem; lsblk; df -h; du -sh *

# User management
useradd -m -s /bin/bash -G sudo username
usermod -aG docker username
passwd username
id username; groups username

# Package management
apt update && apt upgrade -y           # Debian/Ubuntu
yum update / dnf update               # RHEL/CentOS
rpm -qa | grep nginx                   # installed RPMs
dpkg -l | grep nginx                   # installed debs

# Archiving
tar -czvf archive.tar.gz dir/          # create
tar -xzvf archive.tar.gz               # extract
tar -tzvf archive.tar.gz               # list

# Networking
ss -tlnp                               # listening TCP ports
nc -zv host port                       # test connectivity
wget / curl
scp user@host:/path /local/path
rsync -avz --progress src/ dest/
```

## 📚 Resources

- https://linuxcommand.org/
- https://www.tldp.org/LDP/abs/html/ — Bash scripting guide
- https://linuxjourney.com/ — Interactive learning
- https://www.brendangregg.com/linuxperf.html — Performance tools
- https://man7.org/linux/man-pages/ — Man pages online
