-- V3__Balance_Automation.sql
-- ==========================================
-- AUTOMATION: BALANCE SYNC WITH AUTO-FAIL
-- ==========================================
CREATE OR REPLACE FUNCTION fn_sync_account_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_milestone_id   UUID;
    v_milestone_bal  NUMERIC(20,2);
    v_delta_balance  NUMERIC(20,2);
    v_total_calc     NUMERIC(20,2);
    v_stored_balance NUMERIC(20,2);
BEGIN
    -- 1. Atomic Cache Update
    INSERT INTO account_balances (account_id, total_debit, total_credit)
    VALUES (NEW.account_id, 
           (CASE WHEN NEW.direction = 'debit' THEN NEW.amount ELSE 0 END), 
           (CASE WHEN NEW.direction = 'credit' THEN NEW.amount ELSE 0 END))
    ON CONFLICT (account_id) DO UPDATE
    SET total_debit = account_balances.total_debit + EXCLUDED.total_debit,
        total_credit = account_balances.total_credit + EXCLUDED.total_credit,
        last_updated_at = NOW()
    RETURNING current_balance INTO v_stored_balance;

    -- 2. Fetch latest checkpoint
    SELECT milestone_entry_id, verified_balance 
    INTO v_milestone_id, v_milestone_bal
    FROM account_milestones 
    WHERE account_id = NEW.account_id;

    -- 3. Delta Calculation (The "Safety Check")
    -- This is fast because of UUID v7 and your Index
    SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE -amount END), 0)
    INTO v_delta_balance 
    FROM entries 
    WHERE account_id = NEW.account_id
    AND (v_milestone_id IS NULL OR id > v_milestone_id);

    v_total_calc := COALESCE(v_milestone_bal, 0) + v_delta_balance;

    -- 4. The Wall of Integrity
    IF v_total_calc != v_stored_balance THEN
        RAISE EXCEPTION 'SYNC FAILURE: Account % is corrupted. Cache: %, Calculated: %', 
            NEW.account_id, v_stored_balance, v_total_calc;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



CREATE TRIGGER trg_sync_balance
AFTER INSERT ON entries
FOR EACH ROW
EXECUTE FUNCTION fn_sync_account_balance();

--==========================================
-- Optional: You could also add triggers for UPDATE/DELETE if you want to be extra safe, but in a well-designed system, those operations should be disallowed on entries.
--==========================================

CREATE OR REPLACE FUNCTION fn_maintain_milestone(p_account_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO account_milestones (account_id, milestone_entry_id, verified_balance)
    SELECT 
        account_id, 
        (SELECT id FROM entries WHERE account_id = p_account_id ORDER BY id DESC LIMIT 1),
        current_balance
    FROM account_balances
    WHERE account_id = p_account_id
    ON CONFLICT (account_id) DO UPDATE 
    SET milestone_entry_id = EXCLUDED.milestone_entry_id,
        verified_balance = EXCLUDED.verified_balance,
        created_at = NOW();
END;
$$ LANGUAGE plpgsql;