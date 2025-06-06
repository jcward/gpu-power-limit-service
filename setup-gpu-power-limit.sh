#!/usr/bin/env bash
# setup-gpu-power-limit.sh  – Jeff Ward - June 6, 2025, MIT license
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true   # propagates -e through functions

SERVICE_NAME="gpu-power-limit.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
NVIDIA_SMI="$(command -v nvidia-smi || true)"
DEBUG=0

usage() {
  echo "Usage: $0 [--debug|-d]"
  exit 1
}

# ---------- argument parsing -------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug) DEBUG=1 ;;
    -h|--help)  usage ;;
    *) usage ;;
  esac
  shift
done
[[ $DEBUG -eq 1 ]] && set -x

# Print command & line that caused an exit
trap 'echo "❌  Error on line $LINENO: $BASH_COMMAND" >&2' ERR

err() { echo "❌  $1" >&2; exit 1; }

command -v systemctl >/dev/null 2>&1 || err "systemctl not found - this host does not use systemd."
[[ -n "$NVIDIA_SMI" ]] || err "nvidia-smi not found in \$PATH."

# ---------- gather GPU info --------------------------------------------------
mapfile -t GPU_INFO < <(
  "$NVIDIA_SMI" --query-gpu=index,power.min_limit,power.limit,power.max_limit \
                --format=csv,noheader,nounits
)

GPU_COUNT="${#GPU_INFO[@]}"
(( GPU_COUNT > 0 )) || err "No NVIDIA GPUs reported by nvidia‑smi."

echo "Detected NVIDIA GPUs and power limits:"
for line in "${GPU_INFO[@]}"; do
  IFS=',' read -r IDX MIN CUR MAX <<<"$line"
  echo "  GPU$IDX  (min/cur/max W):  $MIN / $CUR / $MAX"
done
echo

# ---------- menu helper ------------------------------------------------------
menu() {
  echo "===== GPU Power‑Limit Service ====="
  echo "1) Install or update $SERVICE_NAME"
  echo "2) Uninstall $SERVICE_NAME"
  echo "3) Monitor draw"
  echo "4) Exit"
  read -rp "Choose an option [1‑4]: " CHOICE
  echo
}

# ---------- install / update -------------------------------------------------
install_service() {
  declare -A LIMITS
  echo "NOTE: setting power limits requires sudo privileges."
  for line in "${GPU_INFO[@]}"; do
    IFS=',' read -r IDX MINF _ MAXF <<<"$line"
    MIN=${MINF%%.*}; MAX=${MAXF%%.*}
    while true; do
      read -rp "Enter new power limit for GPU$IDX (W, ${MIN}-${MAX}): " REQ
      [[ "$REQ" =~ ^[0-9]+$ ]] && (( REQ>=MIN && REQ<=MAX )) && break
      echo "  ► Please enter a number between $MIN and $MAX."
    done
    LIMITS[$IDX]="$REQ"
  done

  # Build chained command
  CMD_CHAIN=""
  for IDX in "${!LIMITS[@]}"; do
    [[ -n "$CMD_CHAIN" ]] && CMD_CHAIN+=" && "
    CMD_CHAIN+="$NVIDIA_SMI -i $IDX -pl ${LIMITS[$IDX]}"
  done

  SERVICE_CONTENT=$(cat <<EOF
[Unit]
Description=GPU power limiter
After=network.target

[Service]
User=root
Type=oneshot
Restart=never
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c "$CMD_CHAIN"

[Install]
WantedBy=multi-user.target
EOF
)

  echo "Writing $SERVICE_PATH ..."
  echo "$SERVICE_CONTENT" | sudo tee "$SERVICE_PATH" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now "$SERVICE_NAME"
  echo -e "\n✅  $SERVICE_NAME installed and running."
}

# ---------- uninstall --------------------------------------------------------
uninstall_service() {
  if sudo test -f "$SERVICE_PATH"; then
    sudo systemctl disable --now "$SERVICE_NAME" || true
    sudo rm -f "$SERVICE_PATH"
    sudo systemctl daemon-reload
    echo "✅  Service removed."
  else
    echo "Service file not found - nothing to uninstall."
  fi
  echo -e "\nTo restore factory power limits, run:"
  for line in "${GPU_INFO[@]}"; do
    IFS=',' read -r IDX _ _ MAXF <<<"$line"
    MAX=${MAXF%%.*}
    echo "  sudo $NVIDIA_SMI -i $IDX -pl $MAX"
  done
}

# ---------- monitor the power draw of the GPUs -------------------------------
monitor_draw() {
  echo -e "\nPress ESC to exit..."
  local old_tty=$(stty -g)          # save tty state
  stty -echo -icanon time 0 min 0    # non‑blocking, no echo

  while true; do
    # query current draw (watts) for every GPU
    mapfile -t DRAW < <(
      "$NVIDIA_SMI" --query-gpu=index,power.draw --format=csv,noheader,nounits
    )

    # build a single status line
    local line=""
    for entry in "${DRAW[@]}"; do
      IFS=',' read -r IDX W <<<"$entry"
      W=${W%%.*}                     # strip decimals
      line+="GPU${IDX} ${W}W "
    done
    printf "\r%-60s" "$line"        # overwrite same line (fallback: scrolls)

    # exit when ESC pressed
    if read -rsn1 -t 0.25 key && [[ $key == $'\e' ]]; then
      break
    fi
  done

  stty "$old_tty"                   # restore tty
  echo                              # move to next line
}

# ---------- main loop --------------------------------------------------------
while true; do
  menu
  case "$CHOICE" in
    1) install_service ;;
    2) uninstall_service ;;
    3) monitor_draw    ;;
    4) echo "Goodbye!"; exit 0 ;;
    *) echo "Invalid choice." ;;
  esac
  echo
done
