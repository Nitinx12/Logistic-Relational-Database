use std::collections::HashMap;

// ======================================================
// MODELS
// ======================================================

#[derive(Debug, Clone)]
struct Customer {
    id: u64,
    name: String,
    email: String,
}

#[derive(Debug, Clone)]
struct Account {
    id: u64,
    customer_id: u64,
    account_type: AccountType,
    balance: f64,
}

#[derive(Debug, Clone)]
enum AccountType {
    Savings,
    Checking,
}

#[derive(Debug, Clone)]
struct Transaction {
    id: u64,
    account_id: u64,
    transaction_type: TransactionType,
    amount: f64,
}

#[derive(Debug, Clone)]
enum TransactionType {
    Deposit,
    Withdrawal,
    TransferIn,
    TransferOut,
    LoanPayment,
}

#[derive(Debug, Clone)]
struct Loan {
    id: u64,
    customer_id: u64,
    principal: f64,
    remaining_balance: f64,
    interest_rate: f64,
}

// ======================================================
// BANK DATABASE
// ======================================================

struct Bank {
    customers: HashMap<u64, Customer>,
    accounts: HashMap<u64, Account>,
    transactions: Vec<Transaction>,
    loans: HashMap<u64, Loan>,

    next_customer_id: u64,
    next_account_id: u64,
    next_transaction_id: u64,
    next_loan_id: u64,
}

impl Bank {
    fn new() -> Self {
        Self {
            customers: HashMap::new(),
            accounts: HashMap::new(),
            transactions: Vec::new(),
            loans: HashMap::new(),

            next_customer_id: 1,
            next_account_id: 1,
            next_transaction_id: 1,
            next_loan_id: 1,
        }
    }

    // ==================================================
    // CUSTOMER
    // ==================================================

    fn create_customer(
        &mut self,
        name: String,
        email: String,
    ) -> u64 {
        let id = self.next_customer_id;
        self.next_customer_id += 1;

        self.customers.insert(
            id,
            Customer {
                id,
                name,
                email,
            },
        );

        id
    }

    // ==================================================
    // ACCOUNT
    // ==================================================

    fn open_account(
        &mut self,
        customer_id: u64,
        account_type: AccountType,
    ) -> u64 {
        let id = self.next_account_id;
        self.next_account_id += 1;

        self.accounts.insert(
            id,
            Account {
                id,
                customer_id,
                account_type,
                balance: 0.0,
            },
        );

        id
    }

    // ==================================================
    // DEPOSIT
    // ==================================================

    fn deposit(
        &mut self,
        account_id: u64,
        amount: f64,
    ) -> Result<(), String> {
        let account = self
            .accounts
            .get_mut(&account_id)
            .ok_or("Account not found")?;

        account.balance += amount;

        self.transactions.push(Transaction {
            id: self.next_transaction_id,
            account_id,
            transaction_type: TransactionType::Deposit,
            amount,
        });

        self.next_transaction_id += 1;

        Ok(())
    }

    // ==================================================
    // WITHDRAW
    // ==================================================

    fn withdraw(
        &mut self,
        account_id: u64,
        amount: f64,
    ) -> Result<(), String> {
        let account = self
            .accounts
            .get_mut(&account_id)
            .ok_or("Account not found")?;

        if account.balance < amount {
            return Err("Insufficient funds".to_string());
        }

        account.balance -= amount;

        self.transactions.push(Transaction {
            id: self.next_transaction_id,
            account_id,
            transaction_type: TransactionType::Withdrawal,
            amount,
        });

        self.next_transaction_id += 1;

        Ok(())
    }

    // ==================================================
    // TRANSFER
    // ==================================================

    fn transfer(
        &mut self,
        from_account: u64,
        to_account: u64,
        amount: f64,
    ) -> Result<(), String> {
        {
            let sender = self
                .accounts
                .get_mut(&from_account)
                .ok_or("Sender account missing")?;

            if sender.balance < amount {
                return Err("Insufficient funds".to_string());
            }

            sender.balance -= amount;
        }

        {
            let receiver = self
                .accounts
                .get_mut(&to_account)
                .ok_or("Receiver account missing")?;

            receiver.balance += amount;
        }

        self.transactions.push(Transaction {
            id: self.next_transaction_id,
            account_id: from_account,
            transaction_type: TransactionType::TransferOut,
            amount,
        });

        self.next_transaction_id += 1;

        self.transactions.push(Transaction {
            id: self.next_transaction_id,
            account_id: to_account,
            transaction_type: TransactionType::TransferIn,
            amount,
        });

        self.next_transaction_id += 1;

        Ok(())
    }

    // ==================================================
    // LOAN
    // ==================================================

    fn create_loan(
        &mut self,
        customer_id: u64,
        principal: f64,
        interest_rate: f64,
    ) -> u64 {
        let id = self.next_loan_id;
        self.next_loan_id += 1;

        self.loans.insert(
            id,
            Loan {
                id,
                customer_id,
                principal,
                remaining_balance: principal,
                interest_rate,
            },
        );

        id
    }

    fn pay_loan(
        &mut self,
        loan_id: u64,
        account_id: u64,
        payment: f64,
    ) -> Result<(), String> {
        self.withdraw(account_id, payment)?;

        let loan = self
            .loans
            .get_mut(&loan_id)
            .ok_or("Loan not found")?;

        loan.remaining_balance -= payment;

        if loan.remaining_balance < 0.0 {
            loan.remaining_balance = 0.0;
        }

        self.transactions.push(Transaction {
            id: self.next_transaction_id,
            account_id,
            transaction_type: TransactionType::LoanPayment,
            amount: payment,
        });

        self.next_transaction_id += 1;

        Ok(())
    }

    // ==================================================
    // REPORTS
    // ==================================================

    fn total_bank_deposits(&self) -> f64 {
        self.accounts
            .values()
            .map(|a| a.balance)
            .sum()
    }

    fn total_loans_outstanding(&self) -> f64 {
        self.loans
            .values()
            .map(|l| l.remaining_balance)
            .sum()
    }

    fn transaction_count(&self) -> usize {
        self.transactions.len()
    }

    fn customer_summary(&self) {
        println!("\nCUSTOMERS");

        for customer in self.customers.values() {
            println!(
                "{} | {} | {}",
                customer.id,
                customer.name,
                customer.email
            );
        }
    }

    fn account_summary(&self) {
        println!("\nACCOUNTS");

        for account in self.accounts.values() {
            println!(
                "Account {} | Customer {} | Balance ${}",
                account.id,
                account.customer_id,
                account.balance
            );
        }
    }

    fn loan_summary(&self) {
        println!("\nLOANS");

        for loan in self.loans.values() {
            println!(
                "Loan {} | Customer {} | Remaining ${}",
                loan.id,
                loan.customer_id,
                loan.remaining_balance
            );
        }
    }

    fn dashboard(&self) {
        println!("\n==============================");
        println!("BANK DASHBOARD");
        println!("==============================");

        println!(
            "Customers: {}",
            self.customers.len()
        );

        println!(
            "Accounts: {}",
            self.accounts.len()
        );

        println!(
            "Loans: {}",
            self.loans.len()
        );

        println!(
            "Transactions: {}",
            self.transaction_count()
        );

        println!(
            "Total Deposits: ${:.2}",
            self.total_bank_deposits()
        );

        println!(
            "Outstanding Loans: ${:.2}",
            self.total_loans_outstanding()
        );

        println!("==============================");
    }
}

// ======================================================
// MAIN
// ======================================================

fn main() {
    let mut bank = Bank::new();

    let alice = bank.create_customer(
        "Alice".to_string(),
        "alice@bank.com".to_string(),
    );

    let bob = bank.create_customer(
        "Bob".to_string(),
        "bob@bank.com".to_string(),
    );

    let alice_account =
        bank.open_account(alice, AccountType::Savings);

    let bob_account =
        bank.open_account(bob, AccountType::Checking);

    bank.deposit(alice_account, 10000.0).unwrap();

    bank.deposit(bob_account, 3000.0).unwrap();

    bank.transfer(
        alice_account,
        bob_account,
        1500.0,
    )
    .unwrap();

    let loan_id =
        bank.create_loan(alice, 50000.0, 8.5);

    bank.pay_loan(
        loan_id,
        alice_account,
        1000.0,
    )
    .unwrap();

    bank.customer_summary();
    bank.account_summary();
    bank.loan_summary();
    bank.dashboard();
}