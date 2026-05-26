# Linux Fundamentals — Brain Map

```
                            ┌─────────────┐
                            │    LINUX    │
                            └──────┬──────┘
           ┌──────────────┬────────┼─────────────┬──────────────┐
           ▼              ▼        ▼              ▼              ▼
      ┌─────────┐   ┌──────────┐ ┌────────┐ ┌─────────┐  ┌──────────┐
      │ Kernel  │   │ Process  │ │  File  │ │ Network │  │Scripting │
      │ Concepts│   │ Mgmt     │ │ System │ │  Stack  │  │  & Tools │
      └────┬────┘   └────┬─────┘ └───┬────┘ └────┬────┘  └────┬─────┘
           │              │           │            │             │
    ┌──────┴──────┐  ┌────┴────┐ ┌───┴────┐ ┌────┴────┐  ┌────┴────┐
    │ Namespaces  │  │fork()   │ │ext4    │ │iptables │  │bash     │
    │ - PID       │  │exec()   │ │xfs     │ │ss/netstat│ │python   │
    │ - NET       │  │wait()   │ │ /proc  │ │tcpdump  │  │awk/sed  │
    │ - MNT       │  │signals  │ │ /sys   │ │curl/wget│  │grep     │
    │ - UTS       │  │daemons  │ │inodes  │ │dig/nslookup│ │find   │
    │ - IPC       │  │zombie   │ │fstab   │ │route    │  │xargs    │
    │ - USER      │  │threads  │ │lsof    │ │            │ │jq      │
    └─────────────┘  └─────────┘ └────────┘ └────────────┘ └────────┘
           │
    ┌──────┴──────┐
    │  cgroups    │
    │ - cpu       │
    │ - memory    │
    │ - blkio     │
    │ - devices   │
    │ - pids      │
    │(base of     │
    │ Docker/K8s) │
    └─────────────┘
```

## Memory Map — Key Commands

```
PROCESS MANAGEMENT                    FILE SYSTEM
───────────────────                   ───────────
ps aux                → all procs     df -h              → disk free
ps -ef --forest       → tree view     du -sh *           → dir sizes
pstree -p             → visual tree   lsof -p PID        → files by proc
kill -SIGTERM PID     → graceful      lsof -i :8080      → port users
kill -SIGKILL PID     → force         stat file          → inode info
nice -n 10 cmd        → lower prio    find / -name "*.log" → search
renice -n 5 -p PID    → change prio   find / -mtime -1d  → recent mods
top / htop            → live view     ln -s target link  → symlink
strace -p PID         → syscall trace dd if=/dev/zero ... → disk test

PERFORMANCE                           NETWORK
───────────                           ───────
vmstat 1              → memory/cpu    ss -tlnp           → open ports
iostat -xz 1          → disk I/O      tcpdump -i eth0    → capture
sar -r 1 10           → memory hist   netstat -s         → stats
perf top              → CPU hotspots  ip addr show       → interfaces
mpstat -P ALL 1       → per-core CPU  ip route show      → routing
free -m               → memory        traceroute host    → path
uptime                → load average  curl -v URL        → HTTP debug
dmesg | tail          → kernel log    dig +trace domain  → DNS trace

SYSTEMD                               SECURITY
───────                               ────────
systemctl status svc  → service state chmod 755 file     → permissions
systemctl start svc   → start         chown user:grp f   → ownership
systemctl enable svc  → boot start    sudo -l            → user perms
journalctl -u svc -f  → follow logs   id username        → user info
systemd-analyze blame → slow boots    auditd             → audit trail
```

## Concept Connection Map

```
  Docker uses ──► NAMESPACES (isolate process view)
  Docker uses ──► CGROUPS (limit resources)
  
  Container = Process(es) + Namespace set + Cgroup limits + Filesystem overlay
  
  K8s Pod    = 1+ Containers sharing PID/NET/IPC namespaces (pause container)
  
  SystemD    = Init process (PID 1) → manages services as cgroups
  
  inode      = File metadata (permissions, size, timestamps, data block pointers)
  hardlink   = Two names → same inode     (no new inode created)
  symlink    = Pointer to another path    (new inode, can span filesystems)
  
  TCP connection lifecycle:
  SYN → SYN-ACK → ACK (established)
  FIN → FIN-ACK → ACK → ACK (close)
  TIME_WAIT: wait 2*MSL before final close
```

## Interview Trigger Words → Concepts

| If asked about... | Think about... |
|------------------|---------------|
| "Container isolation" | namespaces + cgroups |
| "Process is stuck" | strace, lsof, kill signals, zombie vs orphan |
| "Disk full" | df, du, lsof deleted files, inode exhaustion |
| "High CPU" | top, mpstat, perf, CPU-bound vs I/O-bound |
| "Memory leak" | free, /proc/PID/smaps, valgrind, OOM killer |
| "Network slow" | tcpdump, ss, MTU, retransmits, TIME_WAIT |
| "Service won't start" | journalctl -xe, systemctl status, port conflicts |
| "File permissions" | rwxrwxrwx, SUID, SGID, sticky bit, ACLs |
