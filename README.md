# helium_ansible

Ansible playbooks for managing Helium IoT hotspots using systemd services.

## Architecture

This setup uses **systemd services** running **Podman containers** in host network mode:

- **helium-packet-forwarder** - Manages LoRa concentrator communication (UDP port 1680)
- **helium-miner** - Gateway service with gRPC API (port 4467, bound to 127.0.2.1)

Configuration is stored in `/etc/default/` env files, making it easy to customize without modifying systemd units.

**Note:** Services run as root (no `User=` directive in systemd units) to access hardware devices.

## Requirements

### Control Machine

```bash
sudo apt-get install ansible sshpass
```

### Target Device Setup

Flash Raspberry Pi OS Lite (64-bit) to a 32GB or larger microSD card:
https://downloads.raspberrypi.org/raspios_lite_arm64/

After flashing, enable SSH access by creating an empty `ssh` file in the boot partition:
```bash
# On Mac
touch /Volumes/boot/ssh

# On Linux
touch <mount-point>/ssh
```

Connect the device to your network, find its IP address, and copy your SSH key:
```bash
ssh-copy-id pi@<device-ip>
```

Default password is `raspberry`. Test connectivity:
```bash
ssh pi@<device-ip>
```

## Configuration

### Ansible Inventory (hosts.yml)

Configure your target device in `hosts.yml`:
```yaml
all:
  children:
    eu868:  # Change to us915 for US region
      hosts:
        hotspot:
          ansible_host: 192.168.0.12
          ansible_user: pi
          ansible_ssh_pass: raspberry
          ansible_become: true
```

### Host Variables (host_vars/hotspot.yml)

Configure device-specific settings:
```yaml
target_hotspot_vendor: "rakv1"           # Options: cotx, pisces, rakv1, rakv2, sensecap
target_miner_region: "EU868"             # EU868 or US915
target_pf_concentrator_interface: "spi"  # spi or usb
target_pf_concentrator_model: "sx1250"   # sx1250 (sx1302 concentrator)

# Locales
timezone: "Europe/Prague"
wifi_country: "CZ"
```

### Image Versions (roles/miner/defaults/main.yml)

Default image tags (override in host_vars if needed):
```yaml
target_miner_tag: "gateway-latest"
target_pf_image: "ghcr.io/petrkr/sx1302_hal"
target_pf_tag: "0.0.14"
target_pf_concentrator_interface: "spi"  # or "usb"
target_pf_concentrator_model: "sx1250"   # sx1250 only for now
```

### Raspberry Pi Configuration (roles/rpi/defaults/main.yml)

Default Raspberry Pi settings:
```yaml
enable_spi: true
enable_i2c: true
enable_serial_hw: true
locale: "en_US.UTF-8"
xkblayout: "us"
```

Override in host_vars if needed (timezone, wifi_country, etc.).

### Optional: Custom Packet Forwarder Config

If you need a custom packet forwarder configuration file, define in host_vars:
```yaml
packet_forwarder_config_file_path: "/path/to/local_conf.json"
```

This file will be copied to `/home/pi/pf/local_conf.json` on the target device.

## Deployment

Run the playbook to deploy everything:
```bash
ansible-playbook -i hosts.yml rpi.yml
```

This will execute two roles in order:

### Role: `rpi`
1. Upgrade system packages (`apt upgrade dist`)
2. Install basic utilities:
   - `vim`, `mc`, `bat` - editors and file managers
   - `i2c-tools` - I2C device debugging
   - `jq`, `bc` - JSON and math processors
   - `ca-certificates`, `locales-all`
3. Install container engine:
   - `podman` - container runtime
   - `podman-compose` - compose utility (legacy, not used by current setup)
4. Configure Raspberry Pi:
   - Enable SPI and I2C via `raspi-config`
   - Set timezone, locale, wifi country
   - Configure keyboard layout

### Role: `miner`
1. Add `miner` hostname to `/etc/hosts` (127.0.2.1)
2. Create directories (`/home/pi/miner_scripts`, `/home/pi/pf`)
3. Deploy systemd service units to `/etc/systemd/system/`
4. Create env files in `/etc/default/`
5. Enable and start services
6. Copy packet forwarder config (if `packet_forwarder_config_file_path` is defined)

## Service Management

### Check Service Status

```bash
ssh pi@<device-ip>

# Check both services
systemctl status helium-packet-forwarder
systemctl status helium-miner

# View logs
journalctl -u helium-packet-forwarder -f
journalctl -u helium-miner -f
```

### Control Services

```bash
# Restart services
sudo systemctl restart helium-packet-forwarder
sudo systemctl restart helium-miner

# Stop services
sudo systemctl stop helium-miner
sudo systemctl stop helium-packet-forwarder

# Start services
sudo systemctl start helium-packet-forwarder
sudo systemctl start helium-miner
```

### Check Container Status

```bash
# List running containers
podman ps

# View container logs directly
podman logs -f pf
podman logs -f miner
```

## Configuration Files

After deployment, configuration is stored in:

- `/etc/default/helium-packet-forwarder` - Packet forwarder env vars
- `/etc/default/helium-miner` - Miner env vars
- `/etc/systemd/system/helium-packet-forwarder.service` - Packet forwarder systemd unit
- `/lib/systemd/system/helium-miner.service` - Miner systemd unit
- `/home/pi/pf/` - Packet forwarder config directory (for custom local_conf.json)
- `/home/pi/miner_scripts/` - Utility scripts (free_space.sh)

You can edit env files and restart services to apply changes.

## Troubleshooting

### Services won't start

Check systemd logs for errors:
```bash
journalctl -xeu helium-packet-forwarder
journalctl -xeu helium-miner
```

### Images not pulling

Manually pull images:
```bash
podman pull ghcr.io/petrkr/sx1302_hal:0.0.14
podman pull quay.io/team-helium/miner:gateway-latest
```

### Network connectivity issues

Since we use host networking, ensure no firewall rules block:
- UDP 1680 on 127.0.2.1 (packet forwarder → miner communication)
- Outbound connections to Helium network (packet router, API services)

Check if miner is listening:
```bash
ss -ulnp | grep 1680
# Should show: 127.0.2.1:1680
```

### Packet forwarder not detected

Check I2C and SPI devices are accessible:
```bash
ls -l /dev/spidev* /dev/i2c* /dev/gpiomem
```

Ensure the `pi` user has proper permissions (handled by ansible).

## Architecture Details

### Network Mode

Both containers use `--network=host` which means:
- No bridge network overhead
- Direct access to host ports
- Services bind to `127.0.2.1` (loopback alias) for security
- Packet forwarder sends to `127.0.2.1:1680` (miner listen address)

### Device Mappings

**Packet Forwarder:**
- `/dev/spidev0.0`, `/dev/spidev0.1` - SPI for LoRa concentrator
- `/dev/gpiomem` - GPIO access for concentrator control
- Runs with `--privileged` and `SYS_RAWIO` capability

**Miner:**
- Host device mapped to `/dev/i2c-ecc` inside container
  - `/dev/i2c-1:/dev/i2c-ecc` for most vendors (rakv1, rakv2, cotx, sensecap)
  - `/dev/i2c-0:/dev/i2c-ecc` for Pisces vendor
- Uses `ecc://i2c-ecc` keypair URI
- Runs with `SYS_RAWIO` capability

### Environment Variables

Configuration is split between:

**`/etc/default/helium-packet-forwarder`:**
- `VENDOR`, `REGION`, `CONCENTRATOR_INTERFACE`, `CONCENTRATOR_MODEL`
- `IMAGE` - container image with tag

**`/etc/default/helium-miner`:**
- `REGION_OVERRIDE`, `GW_REGION`
- `IMAGE` - container image with tag
- `DEVICE_I2C` - host I2C device path (vendor-specific)

Hardcoded in systemd units (not configurable via env):
- `GW_KEYPAIR=ecc://i2c-ecc`
- `GW_LISTEN=127.0.2.1:1680`
- `GW_API=127.0.2.1:4467`
- `GW_LOG_TIMESTAMP=false`
