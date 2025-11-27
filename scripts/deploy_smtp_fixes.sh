#!/bin/bash
# Quick deployment script for SMTP improvements
# Run this on the production server after deploying code

echo "=========================================="
echo "SMTP Improvements Deployment"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as deploy user or root
if [ "$USER" != "deploy" ] && [ "$EUID" -ne 0 ]; then
   echo -e "${RED}Please run as deploy user or root${NC}"
   exit 1
fi

# Navigate to app directory
cd /home/deploy/CSPM/current || exit 1

echo "1. Checking current email status..."
bundle exec rake email:check_delivery RAILS_ENV=production

echo ""
echo "2. Testing SMTP connection..."
bundle exec rake email:test_smtp RAILS_ENV=production

echo ""
echo "3. Current configuration:"
echo "   SMTP Address: ${SMTP_ADDRESS:-secure.emailsrvr.com}"
echo "   SMTP Port: ${SMTP_PORT:-465}"
echo "   Timeouts: 60s/60s (increased from 30s)"
echo ""

echo "4. Restarting Sidekiq to load new configuration..."
if systemctl is-active --quiet sidekiq; then
    echo -e "${YELLOW}Restarting Sidekiq service...${NC}"
    sudo systemctl restart sidekiq
    sleep 2

    if systemctl is-active --quiet sidekiq; then
        echo -e "${GREEN}✓ Sidekiq restarted successfully${NC}"
    else
        echo -e "${RED}✗ Sidekiq failed to restart${NC}"
        sudo systemctl status sidekiq
        exit 1
    fi
else
    echo -e "${YELLOW}Sidekiq service not running, attempting to start...${NC}"
    sudo systemctl start sidekiq
    sleep 2

    if systemctl is-active --quiet sidekiq; then
        echo -e "${GREEN}✓ Sidekiq started successfully${NC}"
    else
        echo -e "${RED}✗ Sidekiq failed to start${NC}"
        sudo systemctl status sidekiq
        exit 1
    fi
fi

echo ""
echo "5. Checking retry queue after restart..."
bundle exec rake email:check_delivery RAILS_ENV=production

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Monitor logs: tail -f log/sidekiq.log"
echo "  2. Check status: bundle exec rake email:check_delivery RAILS_ENV=production"
echo "  3. If emails stuck: bundle exec rake email:retry_all RAILS_ENV=production"
echo ""
echo "Documentation:"
echo "  - SMTP_PRODUCTION_GUIDE.md - Complete troubleshooting guide"
echo "  - SMTP_CONFIG_FIX.md - Configuration reference"
echo ""
echo "=========================================="

