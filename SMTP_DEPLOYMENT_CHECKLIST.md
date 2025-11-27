# SMTP "554 Error" Fix - Deployment Checklist

## ✅ Pre-Deployment Verification

### 1. Files to Commit
- [x] `config/environments/production.rb` - Enhanced SMTP config
- [x] `config/sidekiq.yml` - Retry configuration
- [x] `config/initializers/sidekiq_email_retry.rb` - Custom retry middleware
- [x] `lib/tasks/email.rake` - Monitoring tasks
- [x] `scripts/deploy_smtp_fixes.sh` - Deployment script
- [x] `SMTP_PRODUCTION_GUIDE.md` - Troubleshooting documentation

### 2. Review Changes
```bash
# Review all changes
git diff config/environments/production.rb
git diff config/sidekiq.yml
git status
```

### 3. Syntax Check
```bash
# All files should be syntax-valid
ruby -c config/environments/production.rb
ruby -c config/initializers/sidekiq_email_retry.rb
ruby -c lib/tasks/email.rake
```

---

## 📦 Deployment Process

### Step 1: Commit Changes
```bash
git add config/environments/production.rb
git add config/sidekiq.yml
git add config/initializers/sidekiq_email_retry.rb
git add lib/tasks/email.rake
git add scripts/deploy_smtp_fixes.sh
git add SMTP_PRODUCTION_GUIDE.md

git commit -m "Implement automatic retry for SMTP '554 not accepting connections' errors

- Increased SMTP timeouts: 30s → 60s (open and read)
- Added Sidekiq retry jitter: 0.25 (prevents thundering herd)
- Created custom retry middleware for email jobs
- Implemented email monitoring rake tasks (check_delivery, test_smtp, stats, etc.)
- Added comprehensive troubleshooting documentation
- Handles Net::SMTPFatalError when server refuses connections
- Emails now retry automatically up to 25 times over 21 days

Fixes: Production email delivery failures with 554 SMTP errors"

git push origin main
```

### Step 2: Deploy to Production
```bash
# If using Capistrano
cap production deploy

# If using manual deployment
# ssh production-server
# cd /path/to/app
# git pull origin main
# bundle install
# ... your deployment process ...
```

### Step 3: SSH to Production Server
```bash
ssh production-server
# Or: ssh deploy@your-server-ip
```

### Step 4: Navigate to App Directory
```bash
cd /home/deploy/CSPM/current
# Or wherever your app is deployed
```

### Step 5: Run Deployment Script
```bash
# Make executable (if not already)
chmod +x scripts/deploy_smtp_fixes.sh

# Run the deployment script
./scripts/deploy_smtp_fixes.sh
```

**What the script does**:
1. ✅ Checks current email delivery status
2. ✅ Tests SMTP connection
3. ✅ Shows current configuration
4. ✅ Restarts Sidekiq
5. ✅ Verifies restart was successful
6. ✅ Shows updated status

### Step 6: Manual Verification (Optional)
```bash
# If script didn't run, do manually:

# 1. Check email status
bundle exec rake email:check_delivery RAILS_ENV=production

# 2. Test SMTP
bundle exec rake email:test_smtp RAILS_ENV=production

# 3. Restart Sidekiq
sudo systemctl restart sidekiq

# 4. Verify Sidekiq is running
sudo systemctl status sidekiq

# 5. Check logs
tail -f log/sidekiq.log
```

---

## ✅ Post-Deployment Verification

### Immediate Checks (0-5 minutes)

- [ ] **Sidekiq Running**
  ```bash
  sudo systemctl status sidekiq
  # Should show: active (running)
  ```

- [ ] **No Errors in Logs**
  ```bash
  tail -50 log/production.log
  # Should not show syntax errors or boot failures
  ```

- [ ] **Rake Tasks Work**
  ```bash
  bundle exec rake email:check_delivery RAILS_ENV=production
  # Should show current status without errors
  ```

- [ ] **SMTP Connection Test**
  ```bash
  bundle exec rake email:test_smtp RAILS_ENV=production
  # May fail with 554 error (expected) or succeed
  ```

### Short-term Monitoring (1-4 hours)

- [ ] **Retry Queue Status** (Check every hour)
  ```bash
  bundle exec rake email:check_delivery RAILS_ENV=production
  # Watch retry queue size - should not grow indefinitely
  ```

- [ ] **Log Monitoring**
  ```bash
  tail -f log/sidekiq.log | grep -i email
  # Watch for retry attempts and successful deliveries
  ```

- [ ] **Stats Check**
  ```bash
  bundle exec rake email:stats RAILS_ENV=production
  # Monitor success rate and error types
  ```

### Long-term Monitoring (24 hours)

- [ ] **Retry Queue Decreasing**
  - Should see retry queue size trending down
  - Most emails should deliver within 4 hours

- [ ] **No Dead Jobs** (or very few)
  ```bash
  bundle exec rake email:check_delivery RAILS_ENV=production
  # Dead queue should be 0 or very small
  ```

- [ ] **Success Rate Improving**
  ```bash
  bundle exec rake email:stats RAILS_ENV=production
  # Overall success rate should be > 95%
  ```

---

## 🚨 Troubleshooting

### Issue: Sidekiq Won't Restart

**Symptoms**:
```bash
sudo systemctl status sidekiq
# Shows: failed or inactive
```

**Solutions**:
```bash
# Check logs
sudo journalctl -u sidekiq -n 50

# Check for syntax errors
cd /home/deploy/CSPM/current
bundle exec rails runner "puts 'OK'"

# Try manual start
bundle exec sidekiq -C config/sidekiq.yml -e production
# Look for error messages
```

### Issue: Rake Tasks Fail

**Symptoms**:
```bash
rake email:check_delivery RAILS_ENV=production
# Shows: error or exception
```

**Solutions**:
```bash
# Verify task is loaded
bundle exec rake -T email
# Should show 5 email tasks

# Check for typos in rake file
ruby -c lib/tasks/email.rake

# Try rails console
bundle exec rails console
> Sidekiq::Stats.new
# Should work without error
```

### Issue: SMTP Test Always Fails

**Symptoms**:
```bash
rake email:test_smtp RAILS_ENV=production
# Always shows: 554 not accepting connections
```

**Expected**: This is **normal** if server is refusing connections

**Solutions**:
- ✅ **Wait 1-2 hours** and test again
- ✅ **Check retry queue** - emails should be retrying
- ✅ **Monitor logs** - should see retry attempts
- ✅ **If persists > 4 hours** - contact Rackspace support

### Issue: Retry Queue Growing

**Symptoms**:
```bash
rake email:check_delivery RAILS_ENV=production
# Shows: retry queue size increasing (50, 100, 200...)
```

**Actions**:
1. **Check SMTP test**:
   ```bash
   rake email:test_smtp RAILS_ENV=production
   ```

2. **Review error types**:
   ```bash
   rake email:stats RAILS_ENV=production
   # Look at error breakdown
   ```

3. **If same error (554)**:
   - This is server-side issue
   - Emails will retry automatically
   - Monitor for 4 hours
   - Contact Rackspace if persists

4. **If different error**:
   - Check credentials
   - Verify configuration
   - Review logs for details

---

## 📊 Success Metrics

### Immediate Success (5 minutes after deployment)

- ✅ Sidekiq restarted successfully
- ✅ No boot errors in logs
- ✅ Rake tasks execute without errors
- ✅ Can run `rake email:check_delivery`

### Short-term Success (1-4 hours)

- ✅ Retry queue size stable or decreasing
- ✅ Some emails delivering successfully
- ✅ Logs show retry attempts with backoff
- ✅ No syntax errors or exceptions

### Long-term Success (24 hours)

- ✅ Retry queue near 0
- ✅ Email success rate > 95%
- ✅ No emails in dead queue
- ✅ SMTP test connects successfully (when server available)

---

## 🔄 Rollback Plan

### If Critical Issues Occur

**When to rollback**:
- Application won't start
- Sidekiq won't start
- Syntax errors in logs
- Critical functionality broken

**Rollback steps**:
```bash
# Using Capistrano
cap production deploy:rollback

# Or manual
cd /home/deploy/CSPM
git log  # Note current commit
git revert HEAD
cap production deploy

# Restart services
sudo systemctl restart sidekiq
```

**After rollback**:
- Emails will still fail with 554 error
- But application will be stable
- Review changes before re-attempting

---

## 📞 Support Contacts

### Internal Team
- **DevOps**: [contact info]
- **Backend Team**: [contact info]
- **On-call**: [contact info]

### External
- **Rackspace Email Support**: support.rackspace.com
- **Server Status**: status.rackspace.com

---

## 📝 Deployment Log

**Date**: November 27, 2025  
**Deployed by**: ______________  
**Deployment time**: ______________  
**Sidekiq restart**: ☐ Success ☐ Failed  
**SMTP test**: ☐ Connected ☐ 554 Error (expected)  
**Retry queue size**: _____ emails  

**Notes**:
_____________________________________________________________
_____________________________________________________________
_____________________________________________________________

**Verified by**: ______________  
**Verification time**: ______________  

---

## ✅ Final Checklist

### Pre-Deployment
- [ ] All files committed
- [ ] Syntax checked
- [ ] Pushed to repository
- [ ] Team notified

### Deployment
- [ ] Code deployed
- [ ] Deployment script executed
- [ ] Sidekiq restarted
- [ ] No errors in logs

### Verification
- [ ] Rake tasks work
- [ ] SMTP test executed
- [ ] Retry queue monitored
- [ ] Logs checked

### Monitoring (1-4 hours)
- [ ] Retry queue stable/decreasing
- [ ] No critical errors
- [ ] Some emails delivering
- [ ] Stats looking good

### Sign-off (24 hours)
- [ ] Retry queue near 0
- [ ] Success rate > 95%
- [ ] No dead jobs
- [ ] Documentation updated

---

**Status**: Ready for Deployment ✅  
**Risk Level**: Low (automatic retry handles failures)  
**Rollback**: Available if needed  
**Monitoring**: Required for 24 hours  

---

**Deployed**: ☐ Not yet ☐ In progress ☐ Complete  
**Working**: ☐ Pending ☐ Verified ☐ Issues  

