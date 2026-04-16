-- V7: Financial Reporting Views
-- This provides the "Human Readable" layer of the ledger.

CREATE OR REPLACE VIEW vw_trial_balance AS
WITH account_sums AS (
    -- Aggregate from the 'entries' table (Ground Truth)
    -- FIX: Use lowercase to match V1/V2 CHECK constraints
    SELECT 
        account_id,
        SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END) as total_debit,
        SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END) as total_credit
    FROM entries
    GROUP BY account_id
)
SELECT 
    a.code AS account_code,
    a.name AS account_name,
    a.type,
    COALESCE(s.total_debit, 0) AS total_debit,
    COALESCE(s.total_credit, 0) AS total_credit,
    -- Calculate net balance based on account category "Normal Balance" rules
    -- Assets/Expenses are Debit-normal; Liabilities/Equity/Revenue are Credit-normal
    CASE 
        WHEN a.type IN ('asset','expense') 
            THEN COALESCE(s.total_debit, 0) - COALESCE(s.total_credit, 0)
        ELSE 
            COALESCE(s.total_credit, 0) - COALESCE(s.total_debit, 0) 
    END AS net_balance
FROM accounts a
-- Use LEFT JOIN so accounts with $0 balance still appear on the report
LEFT JOIN account_sums s ON a.id = s.account_id
ORDER BY a.code;

-- Ledger Health: Total debits must ALWAYS equal total credits
CREATE OR REPLACE VIEW vw_ledger_health AS
SELECT 
    SUM(total_debit) as global_debits,
    SUM(total_credit) as global_credits,
    -- Discrepancy should ideally be 0.00
    (SUM(total_debit) - SUM(total_credit)) as discrepancy
FROM vw_trial_balance;
