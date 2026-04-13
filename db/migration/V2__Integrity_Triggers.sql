-- V2__Integrity_Triggers.sql
-- ==========================================
-- VALIDATION: DOUBLE-ENTRY PRINCIPLES
-- ==========================================

CREATE OR REPLACE FUNCTION fn_enforce_double_entry()
RETURNS TRIGGER AS $$
DECLARE
    v_tx_id UUID := COALESCE(NEW.transaction_id, OLD.transaction_id);
    
    v_debit_sum  NUMERIC(20,2);
    v_credit_sum NUMERIC(20,2);
    v_debit_count  INT;
    v_credit_count INT;
BEGIN

    -- LOCK the header to prevent race conditions
    PERFORM 1 FROM transactions WHERE id = v_tx_id FOR UPDATE;

    -- Aggregate totals for the specific transaction being saved
    SELECT 
        SUM(amount) FILTER (WHERE direction = 'debit'),
        SUM(amount) FILTER (WHERE direction = 'credit'),
        COUNT(*) FILTER (WHERE direction = 'debit'),
        COUNT(*) FILTER (WHERE direction = 'credit')
    INTO 
        v_debit_sum, v_credit_sum, v_debit_count, v_credit_count
    FROM entries
    WHERE transaction_id = v_tx_id;

    -- RULE A: Must have at least one debit and one credit
    IF v_debit_count = 0 OR v_credit_count = 0 THEN
        RAISE EXCEPTION 'Transaction % must have at least one debit and one credit entry.', 
        v_tx_id;
    END IF;

    -- RULE B: Debits must equal Credits
    -- We use COALESCE to treat NULL sums as 0
    IF COALESCE(v_debit_sum, 0) != COALESCE(v_credit_sum, 0) THEN
        RAISE EXCEPTION 'Transaction % is unbalanced. Debits (%) do not equal Credits (%).', 
            v_tx_id, v_debit_sum, v_credit_sum;
    END IF;

    RETURN NULL; -- AFTER triggers ignore the return value
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS trg_validate_entries ON entries;

CREATE CONSTRAINT TRIGGER trg_validate_entries
AFTER INSERT OR UPDATE OR DELETE ON entries
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW
EXECUTE FUNCTION fn_enforce_double_entry();


-- ==========================================
-- IMMUTABILITY GUARD: NO UPDATES, NO DELETES
-- ==========================================

CREATE OR REPLACE FUNCTION fn_block_modifications()
RETURNS TRIGGER AS $$
BEGIN
    -- This blocks both UPDATE and DELETE attempts
    RAISE EXCEPTION 'Immutability Error: You cannot % a recorded % entry (ID: %). To fix a mistake, you must post a reversing transaction.', 
        TG_OP, TG_TABLE_NAME, COALESCE(NEW.id, OLD.id);
    RETURN NULL; -- Execution stops at the RAISE, so this is never reached
END;
$$ LANGUAGE plpgsql;

-- Apply to Transactions (The Header)
CREATE TRIGGER trg_no_edit_transactions
BEFORE UPDATE OR DELETE ON transactions
FOR EACH ROW
EXECUTE FUNCTION fn_block_modifications();

-- Apply to Entries (The Legs)
CREATE TRIGGER trg_no_edit_entries
BEFORE UPDATE OR DELETE ON entries
FOR EACH ROW
EXECUTE FUNCTION fn_block_modifications();

