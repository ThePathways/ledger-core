-- V4__Audit_And_Repair.sql
-- ==========================================
-- Milestone Creation Procedure
-- ==========================================
CREATE OR REPLACE PROCEDURE pr_create_account_milestones()
LANGUAGE plpgsql
AS $$
BEGIN
    -- We remove the explicit isolation set and commit. 
    -- pg_cron runs this in its own transaction automatically.
    
    INSERT INTO account_milestones (account_id, milestone_entry_id, verified_balance)
    WITH latest_entries AS (
        SELECT DISTINCT ON (account_id) 
            account_id, 
            id AS last_id
        FROM entries
        ORDER BY account_id, id DESC
    ),
    calculated_snapshot AS (
        SELECT 
            le.account_id,
            le.last_id,
            SUM(CASE WHEN e.direction = 'debit' THEN e.amount ELSE -e.amount END) as bal
        FROM latest_entries le
        JOIN entries e ON e.account_id = le.account_id AND e.id <= le.last_id
        GROUP BY le.account_id, le.last_id
    )
    SELECT account_id, last_id, bal FROM calculated_snapshot
    ON CONFLICT (account_id) DO UPDATE 
    SET milestone_entry_id = EXCLUDED.milestone_entry_id,
        verified_balance = EXCLUDED.verified_balance,
        created_at = NOW();
END;
$$;

-- ==========================================
-- AUDIT VIEW
-- ==========================================
CREATE OR REPLACE VIEW view_account_integrity_check AS
SELECT 
    a.id AS account_id,
    a.name AS account_name,
    COALESCE(b.current_balance, 0) AS stored_balance,
    (COALESCE(m.verified_balance, 0) + COALESCE(delta.amt, 0)) AS calculated_balance,
    (COALESCE(b.current_balance, 0) - (COALESCE(m.verified_balance, 0) + COALESCE(delta.amt, 0))) AS discrepancy
FROM accounts a
LEFT JOIN account_balances b ON a.id = b.account_id
LEFT JOIN account_milestones m ON a.id = m.account_id
LEFT JOIN LATERAL (
    SELECT SUM(CASE WHEN direction = 'debit' THEN amount ELSE -amount END) as amt
    FROM entries 
    WHERE account_id = a.id 
    -- If no milestone exists, we sum everything from the beginning
    AND (m.milestone_entry_id IS NULL OR id > m.milestone_entry_id)
) delta ON TRUE;

--===========================================
-- REPAIR PROCEDURE (FOR EMERGENCY USE ONLY)
--===========================================

CREATE OR REPLACE PROCEDURE pr_repair_account_integrity(p_account_id UUID)
LANGUAGE plpgsql
AS $$
DECLARE
    v_correct_debit  NUMERIC(20,2);
    v_correct_credit NUMERIC(20,2);
BEGIN
    -- 1. Calculate the actual truth from the immutable entries
    SELECT 
        COALESCE(SUM(amount) FILTER (WHERE direction = 'debit'), 0),
        COALESCE(SUM(amount) FILTER (WHERE direction = 'credit'), 0)
    INTO v_correct_debit, v_correct_credit
    FROM entries
    WHERE account_id = p_account_id;

    -- 2. Force the cache to match the truth
    -- Note: This requires the 'trg_no_edit_entries' to NOT be on this table,
    -- or you must temporarily disable triggers if you put guards on account_balances.
    UPDATE account_balances
    SET total_debit = v_correct_debit,
        total_credit = v_correct_credit,
        last_updated_at = NOW()
    WHERE account_id = p_account_id;

    -- 3. Reset the milestone to this new verified point
    CALL fn_maintain_milestone(p_account_id);
    
    RAISE NOTICE 'Account % has been resynchronized and unlocked.', p_account_id;
END;
$$;