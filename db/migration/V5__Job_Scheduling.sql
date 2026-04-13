
-- V5__Job_Scheduling.sql
-- ============================================================================
-- BACKGROUND MAINTENANCE (pg_cron)
-- ============================================================================

-- Ensure the extension exists. 
-- Note: pg_cron MUST be in 'shared_preload_libraries' in postgresql.conf
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- We wrap the schedule in a DO block to prevent "duplicate job" errors
-- if migrations are re-applied or the baseline is reset.
DO $$
BEGIN
    -- Unschedule if it already exists to ensure we have the latest definition
    PERFORM cron.unschedule('maintain_milestones');
EXCEPTION 
    WHEN OTHERS THEN 
        -- If the job doesn't exist, unschedule throws an error; we catch and ignore it.
        NULL;
END $$;

-- Schedule: Move the milestones forward every 10 minutes for all active accounts.
-- This keeps the "Delta Calculation" in fn_sync_account_balance extremely fast
-- by ensuring the 'entries' scan never has to look back too far in time.
SELECT cron.schedule(
    'maintain_milestones', 
    '*/10 * * * *', 
    'CALL pr_create_account_milestones();'
);

-- Optional: Schedule a weekly "Health Check" to verify all account balances
-- This job doesn't repair, it just ensures the view_account_integrity_check 
-- is processed or can be used to trigger alerts in logs.
SELECT cron.schedule(
    'ledger_integrity_audit',
    '0 0 * * 0', -- Every Sunday at midnight
    $cron$
    DO TRY
        IF EXISTS (SELECT 1 FROM view_account_integrity_check WHERE discrepancy != 0) THEN
            RAISE WARNING 'Ledger Integrity Check Failed: Discrepancies detected.';
        END IF;
    END;
    $cron$
);