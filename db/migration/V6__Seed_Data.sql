-- V6__Seed_Data.sql

-- 1. Create Accounts
INSERT INTO accounts (name, type) VALUES 
('Cash', 'asset'),
('Accounts Receivable', 'asset'),
('Equipment', 'asset'),
('Unearned Revenue', 'liability'),
('Retained Earnings', 'equity'),
('Sales Revenue', 'revenue'),
('Rent Expense', 'expense');
