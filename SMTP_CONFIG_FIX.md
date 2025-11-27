# SMTP Configuration Fix - November 27, 2025

## Issue Summary

**Error**: 
```
ArgumentError: :enable_starttls and :tls are mutually exclusive. 
Set :tls if you're on an SMTPS connection. 
Set :enable_starttls if you're on an SMTP connection and using STARTTLS for secure TLS upgrade.
```

**Root Cause**: 
The SMTP configuration had both `ssl: true` (or `tls: true`) AND `enable_starttls_auto: true` set simultaneously, which are mutually exclusive.

---

## Understanding SMTP Security Modes

### Port 465 - SMTPS (Implicit SSL/TLS)
- Uses **implicit SSL/TLS** from the start
- Connection is encrypted from the beginning
- **Configuration**: `ssl: true`
- **DO NOT USE**: `enable_starttls_auto`

### Port 587 - SMTP with STARTTLS (Explicit TLS)
- Starts as plain text connection
- Upgrades to TLS using **STARTTLS** command
- **Configuration**: `enable_starttls_auto: true`
- **DO NOT USE**: `ssl: true` or `tls: true`

---

## What Was Fixed

### ✅ Production Environment (`config/environments/production.rb`)

**Before** (BROKEN):
```ruby
config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: 465,
  ssl: true,              # ✓ Correct for port 465
  tls: true,              # ✗ Redundant
  enable_starttls_auto: true,  # ✗ WRONG! Conflicts with ssl/tls
  # ...
}
```

**After** (FIXED):
```ruby
config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: 465,              # SMTPS port
  ssl: true,              # ✓ Correct for port 465
  # enable_starttls_auto removed - not needed for port 465
  # ...
}
```

---

### ✅ Development Environment (`config/environments/development.rb`)

**Before** (BROKEN):
```ruby
config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: 465,
  ssl: true,              # ✓ Correct for port 465
  tls: true,              # ✗ Redundant
  enable_starttls_auto: false,  # ✗ Should not be set at all
  # ...
}
```

**After** (FIXED):
```ruby
config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: 465,              # SMTPS port
  ssl: true,              # ✓ Correct for port 465
  # enable_starttls_auto removed completely
  # ...
}
```

---

### ✅ Staging Environment (`config/environments/staging.rb`)

**Status**: Already correct! No changes needed.

```ruby
config.action_mailer.smtp_settings = {
  address: smtp_addr,
  port: smtp_port,
  ssl: (smtp_port == 465),              # ✓ Only if port 465
  enable_starttls_auto: (smtp_port == 587),  # ✓ Only if port 587
  # ...
}
```

This conditional approach is the **recommended pattern** - it sets either `ssl` OR `enable_starttls_auto` based on the port, never both.

---

## Quick Reference Guide

### For Port 465 (SMTPS - Implicit SSL)
```ruby
config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: 465,
  authentication: :plain,
  ssl: true,  # ✓ USE THIS
  # DO NOT set enable_starttls_auto
}
```

### For Port 587 (SMTP with STARTTLS - Explicit TLS)
```ruby
config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: 587,
  authentication: :plain,
  enable_starttls_auto: true,  # ✓ USE THIS
  # DO NOT set ssl or tls
}
```

### For Dynamic Port Selection (Recommended)
```ruby
smtp_port = ENV.fetch('SMTP_PORT', '465').to_i

config.action_mailer.smtp_settings = {
  address: 'secure.emailsrvr.com',
  port: smtp_port,
  authentication: :plain,
  ssl: (smtp_port == 465),              # ✓ Conditional
  enable_starttls_auto: (smtp_port == 587),  # ✓ Conditional
}
```

---

## Testing the Fix

### 1. Restart the Application
```bash
# Development
bin/rails restart

# Production (with Passenger)
passenger-config restart-app /path/to/app

# Production (with systemd)
sudo systemctl restart your-app
```

### 2. Check Sidekiq Logs
```bash
# Watch for SMTP errors
tail -f log/production.log | grep -i smtp

# Check Sidekiq status
bundle exec sidekiq -C config/sidekiq.yml
```

### 3. Test Email Sending
```ruby
# In rails console
UserMailer.status_update_email(user, ticket, current_user, project, assigned_user).deliver_now
```

### 4. Verify Sidekiq Jobs
```bash
# Check failed jobs
rails console
> Sidekiq::RetrySet.new.size
> Sidekiq::DeadSet.new.size

# Clear failed jobs if the error is now fixed
> Sidekiq::RetrySet.new.clear
```

---

## Environment-Specific Settings

| Environment | Port | SSL Mode | Config |
|-------------|------|----------|--------|
| Development | 465 | Implicit SSL | `ssl: true` |
| Staging | Variable | Conditional | `ssl: (port == 465)` + `enable_starttls_auto: (port == 587)` |
| Production | 465 | Implicit SSL | `ssl: true` |

---

## Common SMTP Errors and Solutions

### Error: "ArgumentError: :enable_starttls and :tls are mutually exclusive"
**Solution**: ✅ FIXED - Removed conflicting settings

### Error: "Net::SMTPFatalError: 554 not accepting connections"
**Solution**: This is a server-side issue. The configuration fix should resolve the authentication errors that were causing repeated connection attempts.

### Error: "Net::OpenTimeout: execution expired"
**Solution**: Already configured with increased timeouts:
- `open_timeout: 30`
- `read_timeout: 30`

---

## Deployment Checklist

- [x] Fixed production.rb SMTP config
- [x] Fixed development.rb SMTP config  
- [x] Verified staging.rb is correct
- [x] Removed conflicting `tls` and `enable_starttls_auto` settings
- [x] Added clear comments explaining port differences
- [ ] Deploy to production
- [ ] Restart application
- [ ] Clear Sidekiq retry queue
- [ ] Monitor logs for SMTP errors
- [ ] Test email sending

---

## Additional Notes

### Why Port 465?
Port 465 is the standard SMTPS (SMTP over SSL) port using implicit SSL/TLS. The connection is encrypted from the start.

### Why Not Port 587?
Port 587 uses STARTTLS, which starts unencrypted and then upgrades to TLS. Both are secure, but 465 is simpler as it's encrypted from the beginning.

### Can I Switch to Port 587?
Yes! Just change:
```ruby
port: 587,
enable_starttls_auto: true,
# Remove ssl: true
```

---

## Related Files
- `config/environments/production.rb` - Fixed ✅
- `config/environments/development.rb` - Fixed ✅
- `config/environments/staging.rb` - Already correct ✅

---

**Status**: ✅ **FIXED**  
**Date**: November 27, 2025  
**Issue**: SMTP configuration conflict resolved  
**Next Step**: Deploy and restart application

