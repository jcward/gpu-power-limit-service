# gpu-power-limit-service
A script to create / manage a systemd service to set NVidia GPU power limits

## Why?

In some situations, you need to limit the amount of power your GPUs consume. NVidia GPUs provide
this capability via the `nvidia-smi` tool (a pre-requisite to this service.) This
`setup-gpu-power-limit.sh` script is a one-stop installer / uninstaller, creating a systemd
service to set and maintain your desired power limits at boot.

## Features

- **Auto-detects all NVIDIA GPUs** and shows each card's min / current / max power limits before you choose settings.

- **Interactive menu** to install / update the power-limit service, and uninstall it.

- **Generates a systemd unit** (`gpu-power-limit.service`) that applies your chosen limits on every boot.

- **Monitor option** displays the current power draw of all GPUs.

- **Uninstall option** cleanly stops, disables, and removes the service.

- Optional `--debug` flag turns on bash tracing and prints the exact line on any error for quick troubleshooting.

## Example Setup

The script is interactive - here's an example interaction:

```
user@server:# ./setup-gpu-power-limit.sh
Detected NVIDIA GPUs and power limits:
  GPU0  (min/cur/max W):   100.00 /  200.00 /  350.00

===== GPU Power-Limit Service =====
1) Install or update gpu-power-limit.service
2) Uninstall gpu-power-limit.service
3) Monitor draw
4) Exit
Choose an option [1-4]: 1

NOTE: setting power limits requires sudo privileges.
Enter new power limit for GPU0 (W,  100- 350): 205
Writing /etc/systemd/system/gpu-power-limit.service ...
Created symlink /etc/systemd/system/multi-user.target.wants/gpu-power-limit.service → /etc/systemd/system/gpu-power-limit.service.

✅  gpu-power-limit.service installed and running.

===== GPU Power-Limit Service =====
1) Install or update gpu-power-limit.service
2) Uninstall gpu-power-limit.service
3) Monitor draw
4) Exit
Choose an option [1-4]: 3


Press ESC to exit...
GPU0  42W                                                   

===== GPU Power-Limit Service =====
1) Install or update gpu-power-limit.service
2) Uninstall gpu-power-limit.service
3) Monitor draw
4) Exit

Goodbye!
```

## Helpful Related Info

This info is here just for reference, for manual testing and probing. The script
automates these settings.

Commands:

```
sudo nvidia-smi -q -d POWER    # show current power settings
sudo nvidia-smi -i 0 -pl 250   # manually set the power for GPU 0 to 250 watts
```

And a sample of the unit file generated:

```
[Unit]
Description=GPU power limiter
After=network.target

[Service]
User=root
Type=oneshot
Restart=never
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c "/usr/bin/nvidia-smi -i 0 -pl 205"

[Install]
WantedBy=multi-user.target
```
