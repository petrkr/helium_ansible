# helium_ansible

Ansible playbooks for managing Helium IoT hotspots using systemd services.

## What It Does

This setup deploys:

- **helium-packet-forwarder** - LoRa concentrator communication service
- **helium-miner** - Helium gateway service

Both run as Podman containers managed by systemd services.

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

### Inventory

Add your hotspots to `inventory/hosts.ini`:
```ini
[all:vars]
ansible_user=pi

[hotspots]
animal-name-one ansible_host=192.168.1.10
animal-name-two ansible_host=192.168.1.11
```

### Adding a New Host

1. Add host to `inventory/hosts.ini`:
   ```ini
   [hotspots]
   my-hotspot-name ansible_host=192.168.1.20
   ```

2. Create `host_vars/my-hotspot-name.yml` with configuration:
   ```yaml
   target_hotspot_vendor: "rakv1"
   target_miner_region: "EU868"
   timezone: "Europe/Prague"
   wifi_country: "CZ"
   ```

### Host Variables Reference

Create `host_vars/{animal-name}.yml` for each host with these variables:

**Required:**
```yaml
target_hotspot_vendor: "rakv1"    # Options: cotx, pisces, rakv1, rakv2, sensecap
target_miner_region: "EU868"      # EU868 or US915
```

**Optional:**
```yaml
# Locales & Timezone (if not set, system settings remain unchanged)
timezone: "Europe/Prague"
locale: "en_US.UTF-8"
wifi_country: "CZ"

# Raspberry Pi Hardware
enable_spi: true                                  # Default: true
enable_i2c: true                                  # Default: true
enable_serial_hw: true                            # Default: true

# Packet Forwarder
target_pf_concentrator_interface: "spi"           # Default: spi (or: usb)
target_pf_concentrator_model: "sx1250"            # Default: sx1250
target_pf_image: "ghcr.io/petrkr/sx1302_hal"      # Default: ghcr.io/petrkr/sx1302_hal
target_pf_tag: "0.0.15"                           # Default: 0.0.15

# Miner
target_miner_tag: "gateway-latest"                # Default: gateway-latest
```

## Deployment

Deploy all hotspots:
```bash
ansible-playbook hotspots.yml
```

Deploy a specific hotspot:
```bash
ansible-playbook hotspots.yml --limit animal-name
```

The playbook runs two roles:
- **rpi** - Prepares Raspberry Pi (system packages, Podman, hardware config)
- **miner** - Deploys packet forwarder and miner services

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
podman pull ghcr.io/petrkr/sx1302_hal:0.0.15
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

## Configuration Files on Target

After deployment, configuration is stored in:
- `/etc/default/helium-packet-forwarder` - Packet forwarder environment variables
- `/etc/default/helium-miner` - Miner environment variables
