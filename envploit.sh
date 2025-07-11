#!/bin/bash

# === Color definitions ===
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
CYAN='\e[36m'
MAGENTA='\e[35m'
NC='\e[0m' # No Color

print_banner() {
    local text="ENVPLOIT"
    local colors=("${CYAN}" "${MAGENTA}" "${YELLOW}" "${GREEN}")
    local color=${colors[$RANDOM % ${#colors[@]}]}

    if command -v figlet &>/dev/null; then
        echo -e "${color}$(figlet -f standard "$text")${NC}"
    elif command -v toilet &>/dev/null; then
        echo -e "${color}$(toilet -f mono12 -F metal "$text")${NC}"
    else
        echo -e "${color}=== $text ===${NC}"
    fi
    echo ""
}

print_banner

# === Output Functions ===
print_info()    { echo -e "${YELLOW}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_error()   { echo -e "${RED}[-]${NC} $1"; }

# === Usage Information ===
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [PATH_OR_URL_TO_ENV]

Options:
  -h, --help    Show this help message and exit.

Description:
  This script validates MySQL credentials stored in a .env file.
  It can read from a local file or download a remote .env file via URL.
  Also checks if the MySQL port is open before attempting connection.

Examples:
  $0                      # Use local .env file in current directory
  $0 /path/to/.env        # Use specified local .env file
  $0 https://example.com/.env  # Download and use remote .env file

EOF
}

# === Check port open ===
check_port() {
    local host=$1
    local port=$2

    if command -v nc &>/dev/null; then
        nc -z -w3 "$host" "$port" &>/dev/null
        return $?
    else
        timeout 3 bash -c "echo > /dev/tcp/$host/$port" &>/dev/null
        return $?
    fi
}

# === Parse arguments ===
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

# === File handling ===
ENV_FILE=".env"
TEMP_FILE=""

if [[ "$1" =~ ^https?:// ]]; then
    print_info "Downloading remote .env file from: $1"
    TEMP_FILE=$(mktemp)
    curl -fsSL "$1" -o "$TEMP_FILE"
    if [ $? -ne 0 ]; then
        print_error "Failed to download .env file from URL."
        exit 1
    fi
    ENV_FILE="$TEMP_FILE"
    print_success "Downloaded .env to temporary file."
elif [ -n "$1" ]; then
    ENV_FILE="$1"
    if [ ! -f "$ENV_FILE" ]; then
        print_error "No .env file found at path: $ENV_FILE"
        exit 1
    fi
    print_success "Using local .env file: $ENV_FILE"
else
    if [ ! -f "$ENV_FILE" ]; then
        print_error "No local .env file found in current directory."
        exit 1
    fi
    print_success "Using local .env file: $ENV_FILE"
fi

echo ""
print_info "Loading environment variables from: $ENV_FILE"
echo ""

export $(grep -v '^#' "$ENV_FILE" | sed 's/["'\'']//g' | xargs)

print_info "Parsed key configuration:"
echo ""

printf "%-20s : %s\n" "APP_NAME"      "${APP_NAME:-<not set>}"
printf "%-20s : %s\n" "APP_ENV"       "${APP_ENV:-<not set>}"
printf "%-20s : %s\n" "APP_URL"       "${APP_URL:-<not set>}"
printf "%-20s : %s\n" "DB_HOST"       "${DB_HOST:-<not set>}"
printf "%-20s : %s\n" "DB_PORT"       "${DB_PORT:-3306}"
printf "%-20s : %s\n" "DB_DATABASE"   "${DB_DATABASE:-<not set>}"
printf "%-20s : %s\n" "DB_USERNAME"   "${DB_USERNAME:-<not set>}"
printf "%-20s : %s\n" "MAIL_HOST"     "${MAIL_HOST:-<not set>}"
printf "%-20s : %s\n" "MAIL_USERNAME" "${MAIL_USERNAME:-<not set>}"

echo ""
print_info "Validating required database credentials..."
echo ""

REQUIRED_VARS=("DB_HOST" "DB_PORT" "DB_DATABASE" "DB_USERNAME" "DB_PASSWORD")
MISSING_VAR=0

for var in "${REQUIRED_VARS[@]}"; do
    val="${!var}"
    if [ -z "$val" ]; then
        print_error "Missing variable: $var"
        MISSING_VAR=1
    else
        display_val="$val"
        print_success "$var => '$display_val'"
    fi
done

if [ "$MISSING_VAR" -eq 1 ]; then
    print_error "Validation failed. Some required variables are missing."
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 1
fi

echo ""

print_info "Checking if MySQL port ${DB_PORT:-3306} is open on host $DB_HOST..."
if check_port "$DB_HOST" "${DB_PORT:-3306}"; then
    print_success "Port ${DB_PORT:-3306} is open on $DB_HOST."
else
    print_error "Port ${DB_PORT:-3306} is NOT open on $DB_HOST. Cannot connect."
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 1
fi

echo ""

print_info "Attempting to connect to MySQL database '$DB_DATABASE'..."

mysql -h "$DB_HOST" -P "${DB_PORT:-3306}" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "USE \`$DB_DATABASE\`;" 2>/dev/null

if [ $? -eq 0 ]; then
    print_success "Successfully connected to MySQL database: $DB_DATABASE"
else
    print_error "Failed to connect to MySQL with provided credentials."
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 1
fi

echo ""
print_success "MySQL connection test completed successfully."
echo ""

[ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
