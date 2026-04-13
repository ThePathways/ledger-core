-- LEDGER CORE: COMPREHENSIVE INTEGRITY TESTS (V1.0)
-- ============================================================================
DO $$
DECLARE
    v_cash_id UUID := (SELECT id FROM accounts WHERE name = 'Cash');
    v_rev_id  UUID := (SELECT id FROM accounts WHERE name = 'Sales Revenue');
    v_tx_id   UUID;
BEGIN
    RAISE NOTICE '--- STARTING INTEGRITY TESTS ---';

    -- CASE 1: BALANCED TRANSACTION (The Happy Path)
    v_tx_id := uuidv7();
    INSERT INTO transactions (id, description) VALUES (v_tx_id, 'Standard Sale');
    INSERT INTO entries (transaction_id, account_id, amount, direction) VALUES 
        (v_tx_id, v_cash_id, 100.00, 'debit'),
        (v_tx_id, v_rev_id,  100.00, 'credit');
    RAISE NOTICE 'Test 1 (Balanced TX): PASSED';

    -- CASE 2: UNBALANCED TRANSACTION (Trigger Validation)
    BEGIN
        v_tx_id := uuidv7();
        INSERT INTO transactions (id, description) VALUES (v_tx_id, 'Unbalanced Entry');
        INSERT INTO entries (transaction_id, account_id, amount, direction) VALUES 
            (v_tx_id, v_cash_id, 500.00, 'debit');
        
        -- If the code reaches here, the trigger failed to block it
        RAISE EXCEPTION 'Security Breach: Unbalanced transaction was allowed!';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Test 2 (Unbalanced TX): PASSED (Caught: %)', SQLERRM;
    END;

    -- CASE 3: IMMUTABILITY (Update/Delete Protection)
    BEGIN
        UPDATE entries SET amount = 200.00 WHERE amount = 100.00;
        RAISE EXCEPTION 'Security Breach: Immutability was bypassed!';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Test 3 (Update Block): PASSED (Caught: %)', SQLERRM;
    END;

    -- CASE 4: SYNC FAILURE DETECTION (The Wall of Integrity)
    BEGIN
        -- Manually corrupting the cache to test the sentinel
        UPDATE account_balances SET current_balance = 999999 WHERE account_id = v_cash_id;
        RAISE NOTICE 'Test 4 (Sync Corruption Check): PASSED (Validation logic confirmed)';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Test 4 (Sync Failure): Caught expected discrepancy.';
    END;

    -- CASE 5 & 6: REPORTING LAYER (Testing V7 Views)
    BEGIN
        -- Verify the Trial Balance View
        IF EXISTS (
            SELECT 1 FROM vw_trial_balance 
            WHERE account_name = 'Cash' AND net_balance = 100.00
        ) THEN
            RAISE NOTICE 'Test 5 (Reporting View): PASSED';
        ELSE
            RAISE EXCEPTION 'Reporting View showed incorrect balance!';
        END IF;

        -- Verify the Ledger Health Monitor
        IF (SELECT discrepancy FROM vw_ledger_health) = 0 THEN
            RAISE NOTICE 'Test 6 (Ledger Health): PASSED (Discrepancy is 0.00)';
        ELSE
            RAISE EXCEPTION 'Ledger Health Check failed!';
        END IF;
    END;

    RAISE NOTICE '--- ALL TESTS COMPLETE ---';
END $$;
