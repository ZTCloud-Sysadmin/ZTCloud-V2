```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZTCloud-Sysadmin/ztcl/refs/heads/main/bootstrap.sh)
```

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ZTCloud-Sysadmin/ztcl/refs/heads/main/bootstrap.sh)
```

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ZTCloud-Sysadmin/ztcl/refs/heads/main/bootstrap.sh) --skipconfig --yes
```

```bash
sudo -iu ztcl-sysadmin podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

```bash
sudo -iu ztcl-sysadmin bash -c 'podman inspect --format "{{.Name}}: {{if .State.Healthcheck}}Health={{.State.Healthcheck.Status}}{{else}}No healthcheck{{end}}" $(podman ps -q)'
```

```bash
sudo -iu ztcl-sysadmin podman logs coredns
```