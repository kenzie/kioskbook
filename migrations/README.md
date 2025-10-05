# KioskBook Migrations

This directory contains one-time migration scripts that handle state transitions between versions.

## Purpose

Migrations handle cleanup and transformations that modules shouldn't need to worry about:
- Removing deprecated files and services
- Renaming or relocating files
- Changing ownership or permissions
- Database/config schema changes

Modules remain pure descriptions of the target state.

## Naming Convention

Migrations use date-based naming for merge-safe development:

```
YYYYMMDD_description.sh
```

Examples:
- `20250104_remove_screensaver.sh`
- `20250115_dedicated_user_migration.sh`
- `20250203_cleanup_old_repos.sh`

## Migration Format

Each migration is a bash script with:
- Idempotency checks (safe to run multiple times)
- Clear logging of actions
- Error handling

Example:
```bash
#!/bin/bash
#
# Migration: Remove deprecated screensaver service
# Created: 2025-01-04
#

set -euo pipefail

# Source common functions if needed
if [[ -f /opt/kioskbook-repo/lib/common.sh ]]; then
    source /opt/kioskbook-repo/lib/common.sh
fi

log_migration() {
    echo "[MIGRATION $(basename "$0")] $1"
}

# Idempotency check
if systemctl list-unit-files | grep -q kioskbook-screensaver; then
    log_migration "Removing screensaver service..."
    systemctl stop kioskbook-screensaver 2>/dev/null || true
    systemctl disable kioskbook-screensaver 2>/dev/null || true
    rm -f /etc/systemd/system/kioskbook-screensaver.service
    systemctl daemon-reload
    log_migration "Screensaver service removed"
else
    log_migration "Screensaver service not found, skipping"
fi
```

## Execution

Migrations are run automatically during `kiosk update all`:
1. Git pulls latest changes
2. Runs pending migrations (newer than last migration version)
3. Runs modules to ensure target state
4. Updates migration version tracker

Migration tracking file: `/etc/kioskbook/migration-version`

## Development Workflow

1. Create migration with today's date:
   ```bash
   vim migrations/$(date +%Y%m%d)_my_migration.sh
   chmod +x migrations/$(date +%Y%m%d)_my_migration.sh
   ```

2. Test locally on dev kiosk:
   ```bash
   sudo bash migrations/$(date +%Y%m%d)_my_migration.sh
   ```

3. Commit and push when confirmed working

4. Deploy to production kiosks:
   ```bash
   sudo kiosk update all
   ```

## Best Practices

- **Idempotent**: Always safe to run multiple times
- **Logged**: Clear output about what's happening
- **Safe**: Check before deleting/modifying
- **Documented**: Comments explain why migration exists
- **Tested**: Run on dev system before committing
