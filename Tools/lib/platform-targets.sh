# Shared deployment policy for both DriverKit build paths. Does not touch hardware.
# SDK version is selected by xcrun; deployment floor is independent of SDK version.
MAESTRO_PLATFORM_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/platform-compatibility.json"
MAESTRO_DRIVERKIT_BASELINE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["minimumDriverKit"])' "$MAESTRO_PLATFORM_CONFIG")"
if [ -n "${MAESTRO_DRIVERKIT_DEPLOYMENT_TARGET:-}" ] && [ "$MAESTRO_DRIVERKIT_DEPLOYMENT_TARGET" != "$MAESTRO_DRIVERKIT_BASELINE" ]; then
    echo "DriverKit override conflicts with shared deployment policy ($MAESTRO_DRIVERKIT_BASELINE)" >&2
    return 2
fi
MAESTRO_DRIVERKIT_DEPLOYMENT_TARGET="$MAESTRO_DRIVERKIT_BASELINE"
