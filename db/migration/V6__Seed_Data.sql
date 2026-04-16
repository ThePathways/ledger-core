-- V6__Seed_Data.sql

-- 1. Create Accounts
INSERT INTO accounts (code, name, type) VALUES 
('1000', 'Cash', 'asset'),
('1010', 'Accounts Receivable', 'asset'),
('1200', 'Equipment', 'asset'),
('2000', 'Unearned Revenue', 'liability'),
('3000', 'Retained Earnings', 'equity'),
('4000', 'Sales Revenue', 'revenue'),
('5000', 'Rent Expense', 'expense');
