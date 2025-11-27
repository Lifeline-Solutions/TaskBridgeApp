# SMTP Configuration Fix - Deployment Checklist

## ✅ Pre-Deployment Verification

### 1. Configuration Files Fixed
- [x] `config/environments/production.rb` - Removed conflicting TLS/STARTTLS settings
- [x] `config/environments/development.rb` - Removed conflicting TLS/STARTTLS settings
- [x] `config/environments/staging.rb` - Already correct (conditional pattern)

### 2. Verification Script Confirms Fix
```bash
$ ruby scripts/verify_smtp_config.rb

Environment: DEVELOPMENT
  Port: 465
  SSL setting: ✓ present
  TLS setting: ✗ not set
  STARTTLS setting: ✗ not set
  ✅ Configuration looks correct!

Environment: STAGING
  Port: (variable: smtp_port)
  SSL setting: ✓ present
  TLS setting: ✗ not set
  STARTTLS setting: ✓ present
  ✅ Conditional SSL/STARTTLS configuration detected (staging pattern)
  ✅ Configuration looks correct!

Environment: PRODUCTION
  Port: 465
  SSL setting: ✓ present
  TLS setting: ✗ not set
  STARTTLS setting: ✗ not set
  ✅ Configuration looks correct!
```

---

## 📋 Deployment Steps

### Step 1: Commit and Push Changes
```bash
cd /home/abol-ger/Desktop/Projects/tasker/CSPM

# Review changes
git diff config/environments/

# Stage changes
git add config/environments/production.rb
git add config/environments/development.rb
git add scripts/verify_smtp_config.rb
git add SMTP_CONFIG_FIX.md

# Commit
git commit -m "Fix SMTP configuration - remove conflicting TLS/STARTTLS settings

- Removed 'tls: true' and 'enable_starttls_auto' from production.rb
- Removed 'tls: true' and 'enable_starttls_auto' from development.rb
- Port 465 now uses only 'ssl: true' (implicit SSL)
- Added verification script and documentation
- Fixes ArgumentError: :enable_starttls and :tls are mutually exclusive"

# Push to repository
git push origin main  # or your branch name
```

### Step 2: Deploy to Staging (Test First)
```bash
# If using Capistrano
cap staging deploy

# Verify staging deployment
cap staging deploy:check
```

### Step 3: Restart Staging Application
```bash
# SSH to staging server
ssh staging-server

# Restart application (choose one based on your setup)
# Option A: Passenger
passenger-config restart-app /path/to/cspm

# Option B: Systemd
sudo systemctl restart cspm

# Restart Sidekiq
sudo systemctl restart sidekiq
```

### Step 4: Test Email on Staging
```bash
# On staging server, in rails console
rails console

# Test email delivery
user = User.first
ticket = Ticket.first
project = ticket.project
assigned_user = user

UserMailer.status_update_email(user, ticket, user, project, assigned_user).deliver_now
# Should return successfully without ArgumentError
```

### Step 5: Monitor Staging Logs
```bash
# Watch for SMTP errors
tail -f log/production.log | grep -i smtp

# Check Sidekiq
tail -f log/sidekiq.log

# Should see successful email deliveries, no ArgumentError
```

### Step 6: Clear Sidekiq Retry Queue on Staging
```bash
# In rails console on staging
Sidekiq::Stats.new.retry_size  # Check retry queue size
Sidekiq::RetrySet.new.clear     # Clear retry queue

Sidekiq::Stats.new.dead_size    # Check dead queue size
# Only clear dead queue if you're confident:
# Sidekiq::DeadSet.new.clear
```

### Step 7: Deploy to Production (After Staging Verified)
```bash
# If using Capistrano
cap production deploy

# Verify production deployment
cap production deploy:check
```

### Step 8: Restart Production Application
```bash
# SSH to production server
ssh production-server

# Restart application (choose one based on your setup)
# Option A: Passenger
passenger-config restart-app /home/deploy/CSPM/current

# Option B: Systemd
sudo systemctl restart cspm

# Restart Sidekiq
sudo systemctl restart sidekiq
```

### Step 9: Clear Production Sidekiq Queues
```bash
# In rails console on production
rails console

# Check queue sizes
Sidekiq::Stats.new.retry_size
Sidekiq::Stats.new.dead_size

# Clear retry queue (failed jobs will retry with new config)
Sidekiq::RetrySet.new.clear

# Optionally clear dead queue if you're confident
# Sidekiq::DeadSet.new.clear
```

### Step 10: Monitor Production
```bash
# Watch logs
tail -f log/production.log | grep -i smtp
tail -f log/sidekiq.log

# Monitor for 10-15 minutes to ensure:
# 1. No ArgumentError
# 2. Emails sending successfully
# 3. No new SMTP errors
```

---

## ✅ Post-Deployment Verification

### Check 1: No ArgumentError in Logs
```bash
# Should return nothing
grep -i "ArgumentError.*starttls.*tls" log/production.log
grep -i "mutually exclusive" log/production.log
```

### Check 2: Email Jobs Succeeding
```bash
# In rails console
Sidekiq::Stats.new.processed  # Should be increasing
Sidekiq::Stats.new.failed     # Should not be increasing
```

### Check 3: Test Real Email
```bash
# In production rails console
user = User.where(email: 'your-email@craftsilicon.com').first
ticket = Ticket.last
project = ticket.project
assigned_user = ticket.users.first || user

UserMailer.status_update_email(user, ticket, user, project, assigned_user).deliver_now
# Check your email - should receive it
```

### Check 4: Verify SMTP Configuration
```bash
# On production server
cd /home/deploy/CSPM/current
bundle exec rails runner scripts/verify_smtp_config.rb

# Should show:
# Environment: PRODUCTION
#   ✅ Configuration looks correct!
```

---

## 🚨 Rollback Plan (If Issues Occur)

### Quick Rollback
```bash
# If using Capistrano
cap production deploy:rollback

# Restart application
ssh production-server
passenger-config restart-app /home/deploy/CSPM/current
sudo systemctl restart sidekiq
```

### Manual Rollback
```bash
# Revert the commit
git revert HEAD
git push origin main

# Redeploy
cap production deploy
```

---

## 📊 Success Metrics

After 1 hour of deployment, verify:
- [ ] Zero "ArgumentError" related to SMTP in logs
- [ ] Email delivery success rate > 95%
- [ ] Sidekiq retry queue not growing
- [ ] No new SMTP fatal errors
- [ ] Users receiving email notifications

---

## 🔍 Troubleshooting

### If emails still fail with different error:

#### Error: "Net::SMTPFatalError: 554 not accepting connections"
**Cause**: Server-side issue at secure.emailsrvr.com  
**Solution**: Wait and retry, or contact email provider

#### Error: "Net::OpenTimeout"
**Cause**: Network/firewall issue  
**Solution**: Already configured with 30s timeouts, verify network connectivity

#### Error: "Net::SMTPAuthenticationError: 535 authentication failed"
**Cause**: Wrong credentials  
**Solution**: Verify username/password in environment config

---

## 📝 Documentation Files Created

1. ✅ `SMTP_CONFIG_FIX.md` - Detailed technical explanation
2. ✅ `scripts/verify_smtp_config.rb` - Configuration verification script
3. ✅ `DEPLOYMENT_CHECKLIST.md` - This file

---

## 🎉 Expected Result

After deployment:
- ✅ No more "ArgumentError: :enable_starttls and :tls are mutually exclusive"
- ✅ Emails sending successfully via SMTPS (port 465)
- ✅ Sidekiq jobs processing normally
- ✅ Users receiving email notifications

---

## 📞 Support

If issues persist after deployment:
1. Check logs: `tail -f log/production.log | grep -i smtp`
2. Verify config: `rails runner scripts/verify_smtp_config.rb`
3. Test email: `rails console` → send test email
4. Review SMTP_CONFIG_FIX.md for detailed explanation

---

**Deployment Date**: _____________  
**Deployed By**: _____________  
**Production Restart Time**: _____________  
**Verification Complete**: [ ] Yes [ ] No  

---

**Status**: Ready for deployment ✅

