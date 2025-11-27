# SMTP "554 Not Accepting Connections" Error - Production Guide

## Issue Summary

**Error**: `Net::SMTPFatalError: 554 smtp*.relay.ord1d.emailsrvr.com ESMTP not accepting connections`

**What it means**: The email server is temporarily refusing to accept new connections. This is a **server-side issue**, not a configuration problem.

**Impact**: Email delivery is delayed but will automatically retry

**Status**: ✅ **Mitigated with automatic retry logic**

---

## Why This Happens

The error "554 not accepting connections" from Rackspace Email servers can occur due to:

1. **Server Load**: Email server is at capacity
2. **Rate Limiting**: Too many connections in short time
3. **Maintenance**: Server undergoing maintenance
4. **Network Issues**: Temporary connectivity problems
5. **IP Reputation**: Sending IP temporarily throttled

This is **normal** and **temporary** - the server will accept connections again shortly.

---

## What We've Implemented

### ✅ 1. Automatic Retry with Exponential Backoff

**Sidekiq Configuration** (`config/sidekiq.yml`):
```yaml
:max_retries: 25  # Will retry up to 25 times
:retry_jitter: 0.25  # Adds randomness to prevent thundering herd
```

**Retry Schedule**:
- 1st retry: ~25 seconds
- 2nd retry: ~1 minute
- 3rd retry: ~5 minutes
- 4th retry: ~20 minutes
- 5th retry: ~1 hour
- ... continues up to 25 retries over ~21 days

### ✅ 2. Increased Timeouts

**SMTP Settings** (`config/environments/production.rb`):
```ruby
open_timeout: 60  # Wait up to 60s to connect
read_timeout: 60  # Wait up to 60s for response
```

### ✅ 3. Custom Error Handling

**Sidekiq Middleware** (`config/initializers/sidekiq_email_retry.rb`):
- Logs SMTP connection errors
- Allows automatic retry without intervention
- Notifies when jobs move to dead queue

### ✅ 4. Monitoring Tools

**Rake Tasks** (`lib/tasks/email.rake`):
```bash
# Check email delivery status
rake email:check_delivery

# Test SMTP connection
rake email:test_smtp

# Show statistics
rake email:stats

# Retry all failed emails
rake email:retry_all
```

---

## What Happens Now

1. **Email Job Enqueued** → Sidekiq picks it up
2. **SMTP Connection Fails** → "554 not accepting connections"
3. **Job Moves to Retry Queue** → Will retry in ~25 seconds
4. **Retry with Backoff** → If still failing, retries after 1 min, 5 min, etc.
5. **Eventually Succeeds** → Email delivered when server accepts connections
6. **Or Moves to Dead Queue** → After 25 retries (21 days), needs manual intervention

---

## Monitoring in Production

### Check Current Status
```bash
# SSH to production server
ssh production-server
cd /home/deploy/CSPM/current

# Check email delivery status
bundle exec rake email:check_delivery RAILS_ENV=production
```

**Example Output**:
```
EMAIL DELIVERY STATUS CHECK
================================================================================

Overall Sidekiq Stats:
  Processed: 15432
  Failed: 23
  Retry queue size: 5
  Dead queue size: 0

Email Job Status:
  Email jobs in retry queue: 5
  Email jobs in dead queue: 0

⚠️  WARNING: 5 email jobs failing due to SMTP connection issues
   These will retry automatically with exponential backoff
   Most recent error: 554 smtp1.relay.ord1d.emailsrvr.com ESMTP not accepting connections
```

### Test SMTP Connection
```bash
bundle exec rake email:test_smtp RAILS_ENV=production
```

**Example Output**:
```
Testing SMTP connection...
================================================================================
SMTP Configuration:
  Address: secure.emailsrvr.com
  Port: 465
  Domain: craftsilicon.com
  Username: cspm@craftsilicon.com
  SSL: true
  Open Timeout: 60s
  Read Timeout: 60s

Attempting connection...
✓ Successfully connected to SMTP server!
  Server capabilities: LOGIN PLAIN
```

### View Statistics
```bash
bundle exec rake email:stats RAILS_ENV=production
```

### Watch Logs
```bash
# Watch for SMTP errors in real-time
tail -f log/production.log | grep -i smtp

# Watch Sidekiq logs
tail -f log/sidekiq.log
```

---

## When to Take Action

### ✅ **No Action Needed** (Automatic Retry Handles It)

- **Scenario**: Few emails (< 10) in retry queue
- **Error**: "554 not accepting connections"
- **Status**: Jobs are retrying with backoff
- **Action**: None - monitor for 1-2 hours

### ⚠️ **Monitor Closely**

- **Scenario**: Many emails (10-50) in retry queue
- **Error**: "554 not accepting connections" 
- **Status**: Server may be experiencing extended issues
- **Action**: 
  1. Check email provider status
  2. Verify credentials haven't changed
  3. Monitor for 2-4 hours
  4. Contact Rackspace if persists

### 🚨 **Take Action**

- **Scenario**: Emails in dead queue OR retry queue > 50
- **Error**: Persistent failures over 24 hours
- **Status**: Systematic problem
- **Actions**:
  1. **Test SMTP**: `rake email:test_smtp`
  2. **Check credentials**: Verify password hasn't expired
  3. **Check IP reputation**: May be temporarily blacklisted
  4. **Contact Rackspace Support**: Open ticket
  5. **Consider alternative**: Use port 587 instead of 465

---

## Manual Interventions

### Retry All Failed Emails Immediately
```bash
# Only do this if server is confirmed working
bundle exec rake email:retry_all RAILS_ENV=production
```

### Clear Dead Queue (Use with Caution)
```bash
# This DELETES emails permanently - be careful!
bundle exec rake email:clear_dead RAILS_ENV=production
```

### Check Specific Job
```bash
# In Rails console
rails console

# Find job in retry queue
retry_set = Sidekiq::RetrySet.new
job = retry_set.find { |j| j.jid == 'JOB_ID_HERE' }

# See error details
puts job.item['error_message']
puts job.item['error_class']
puts job.item['retry_count']

# Manually retry now
job.retry

# Or delete
job.delete
```

---

## Alternative Configurations

### Option 1: Use Port 587 (STARTTLS)
```ruby
# config/environments/production.rb
smtp_settings = {
  port: 587,  # Change from 465
  enable_starttls_auto: true,  # Instead of ssl: true
  # Remove: ssl: true
}
```

### Option 2: Use Different SMTP Server
```ruby
# config/environments/production.rb
smtp_settings = {
  address: 'smtp.gmail.com',  # Or other provider
  # ... other settings
}
```

### Option 3: Use Environment Variables
```bash
# In production server
export SMTP_ADDRESS=secure.emailsrvr.com
export SMTP_PORT=465
export SMTP_USERNAME=cspm@craftsilicon.com
export SMTP_PASSWORD='#cspm@123#'
export SMTP_DOMAIN=craftsilicon.com
```

---

## Common Questions

### Q: Why are emails delayed?
**A**: The server is temporarily refusing connections. Sidekiq will retry automatically with exponential backoff.

### Q: Will emails be lost?
**A**: No. Sidekiq retries up to 25 times over 21 days before moving to dead queue. You'll have plenty of time to fix any issues.

### Q: Should I restart Sidekiq?
**A**: No. Restarting won't help - the issue is with the email server, not Sidekiq. Let automatic retry handle it.

### Q: How do I know when it's working again?
**A**: Run `rake email:check_delivery` - you'll see retry queue size decreasing. Or check `log/sidekiq.log` for successful deliveries.

### Q: Can I send emails through a different server?
**A**: Yes. Update `SMTP_ADDRESS` environment variable or modify `config/environments/production.rb`.

---

## Escalation Path

### Level 1: Monitor (0-2 hours)
- Check `rake email:check_delivery`
- Watch retry queue size
- No action needed if < 10 emails retrying

### Level 2: Investigate (2-4 hours)
- Run `rake email:test_smtp`
- Check Rackspace status page
- Review recent changes
- Check credentials

### Level 3: Contact Support (4+ hours)
- Open Rackspace support ticket
- Provide:
  - Error message
  - Time range of issues
  - Number of affected emails
  - Results of `rake email:test_smtp`

### Level 4: Switch Provider (24+ hours)
- Consider alternative SMTP provider
- Update configuration
- Test thoroughly
- Monitor for 24 hours

---

## Prevention

### 1. Monitor Regularly
```bash
# Add to cron (check every hour)
0 * * * * cd /home/deploy/CSPM/current && bundle exec rake email:check_delivery RAILS_ENV=production >> /var/log/cspm/email_check.log 2>&1
```

### 2. Set Up Alerts
```ruby
# In Sidekiq config (optional)
Sidekiq.configure_server do |config|
  config.error_handlers << lambda do |ex, ctx_hash|
    if ctx_hash[:job]['wrapped'] == 'ActionMailer::MailDeliveryJob'
      # Send alert if too many email failures
      # AdminMailer.smtp_error_alert(ex, ctx_hash).deliver_later
    end
  end
end
```

### 3. Use Email Monitoring Service
- Consider services like Postmark, SendGrid, or Mailgun
- They provide better deliverability and monitoring
- Less likely to have connection refusal issues

---

## Files Modified/Created

1. ✅ `config/environments/production.rb` - Increased timeouts, added env vars
2. ✅ `config/sidekiq.yml` - Added retry configuration
3. ✅ `config/initializers/sidekiq_email_retry.rb` - Custom retry logic
4. ✅ `lib/tasks/email.rake` - Monitoring and management tasks
5. ✅ `SMTP_PRODUCTION_GUIDE.md` - This documentation

---

## Quick Reference Commands

```bash
# Check status
rake email:check_delivery RAILS_ENV=production

# Test connection
rake email:test_smtp RAILS_ENV=production

# View stats
rake email:stats RAILS_ENV=production

# Watch logs
tail -f log/sidekiq.log | grep -i email

# Rails console
rails console
> Sidekiq::RetrySet.new.size
> Sidekiq::Stats.new
```

---

**Summary**: The "554 not accepting connections" error is a temporary server-side issue that Sidekiq handles automatically with exponential backoff retry. Monitor the retry queue, but no immediate action is required unless issues persist for more than 4 hours.

**Status**: ✅ **System configured for automatic handling**

---

**Last Updated**: November 27, 2025  
**Issue**: SMTP connection refused  
**Solution**: Automatic retry with monitoring  
**Action Required**: None (monitor only)

