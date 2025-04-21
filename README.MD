```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZTCloud-Sysadmin/ztcl/refs/heads/main/bootstrap.sh)
```

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ZTCloud-Sysadmin/ztcl/refs/heads/main/bootstrap.sh)
```

```bash
sudo -iu ztcl-sysadmin podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

```bash
sudo -iu ztcl-sysadmin bash -c 'podman inspect --format "{{.Name}}: {{if .State.Healthcheck}}Health={{.State.Healthcheck.Status}}{{else}}No healthcheck{{end}}" $(podman ps -q)'
```

```bash
sudo -iu ztcl-sysadmin podman logs coredns
sudo -iu ztcl-sysadmin podman restart headscale
```

```bash
sudo systemctl status ztcloud
sudo -iu ztcl-sysadmin podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

``bash
tailscale status
tailscale ip -4
```
b