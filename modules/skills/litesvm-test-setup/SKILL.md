---
name: litesvm-test-setup
description: Set up LiteSVM-based Rust integration tests for Anchor programs, including auto-building .so files and resolving version/type conflicts.
---

# LiteSVM Rust Test Setup for Anchor Programs

Configure Rust integration tests using LiteSVM to test Anchor programs without a live validator.

## When to use

- Writing Rust integration tests for Anchor programs (not TypeScript)
- Need fast, in-process Solana program testing
- `cargo test` for program integration tests
- Avoiding solana-test-validator overhead

## Prerequisites

- Anchor CLI (for `anchor build`)
- Program must be buildable (Anchor.toml configured)

## Steps

### 1. Add dependencies

In the program's `Cargo.toml`:

```toml
[dev-dependencies]
litesvm = "0.13"
anchor-litesvm = "0.4"
solana-keypair = "2"
solana-message = "2"
solana-pubkey = "2"
solana-signer = "2"
solana-system-interface = "2"
solana-transaction = "2"
```

**Important version notes:**
- `litesvm 0.13.x` hard-pins `solana-instruction = "=3.2.0"` which may conflict with solana 4.x crates. Use `anchor-litesvm 0.4.x` which bridges anchor-lang 1.x and litesvm without conflicts.
- If using `blake3` in program code: must be in `[dependencies]` (not dev-deps) with `default-features = false` to disable C/ASM optimizations incompatible with SBF.

### 2. Create build.rs to auto-build .so

The `.so` file must exist before tests run. Add a `build.rs` in the test crate (or program crate) to auto-build on first run:

```rust
use std::path::Path;
use std::process::{Command, Stdio};

fn main() {
    let so_path = Path::new("../../target/deploy/lottery.so"); // adjust path
    println!("cargo:rerun-if-changed={}", so_path.display());

    if !so_path.exists() {
        eprintln!("{} not found, building with anchor build...", so_path.display());
        let status = Command::new("anchor")
            .current_dir("../../..")  // repo root
            .args(["build", "--program-name", "lottery"])
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()
            .expect("Failed to spawn anchor build");

        if !status.success() {
            panic!("anchor build failed with status: {}", status);
        }
    }
}
```

Stream stdout/stderr to parent so build output is visible. Use `Stdio::inherit()` not `Stdio::piped()`.

### 3. Write the test

```rust
#![cfg(test)]

use std::path::Path;
use std::sync::LazyLock;

use anchor_lang::solana_program::{instruction::Instruction, system_program};
use anchor_lang::{prelude::*, AccountDeserialize, InstructionData};
use litesvm::LiteSVM;
use my_program::{self, id, MyAccount, MY_ACCOUNT_SEED};
use solana_keypair::Keypair;
use solana_message::Message;
use solana_pubkey::Pubkey;
use solana_signer::Signer;
use solana_system_interface::instruction::transfer;
use solana_transaction::Transaction;

static PROGRAM_BYTES: LazyLock<Vec<u8>> = LazyLock::new(|| {
    std::fs::read("../../target/deploy/my_program.so")
        .expect("Failed to read program .so file")
});

#[test]
fn test_my_instruction() {
    let mut svm = LiteSVM::new();

    // Load program — use Pubkey, not Address
    svm.add_program(my_program::ID, &PROGRAM_BYTES);

    // Fund payer
    let payer = Keypair::new();
    svm.airdrop(&payer.pubkey(), 10_000_000_000).unwrap();

    // Create account + invoke instruction
    let counter = Keypair::new();
    let ix = Instruction {
        program_id: my_program::ID,
        accounts: vec![
            AccountMeta::new(payer.pubkey(), true, true),
            AccountMeta::new(counter.pubkey(), true, true),
            AccountMeta::new_readonly(system_program::ID, false),
        ],
        data: MyInstructionData { data: 42 }.try_to_vec().unwrap(),
    };

    let msg = Message::new(&[ix], Some(&payer.pubkey()));
    let tx = Transaction::new(&[&payer, &counter], msg, svm.latest_blockhash());
    let result = svm.process_transaction(tx);
    assert!(result.is_ok());
}
```

### 4. Common issues

| Error | Cause | Fix |
|---|---|---|
| `expected Pubkey, found Address` | Using `program::ID` with newer anchor-lang that exports `Address` type | Convert: `Pubkey::new(program::ID.as_ref())` or use the `Pubkey` type from solana-pubkey |
| `InsufficientFundsForRent` | Account not funded before instruction | Call `svm.airdrop()` on all signers before the transaction |
| `DeclaredProgramIdMismatch` | Program loaded with wrong ID | Ensure `svm.add_program(ID, bytes)` uses the correct program ID from the program's `id()` function |
| `program .so not found` at compile time | build.rs didn't run or anchor build failed | Run `anchor build --program-name <name>` manually first, check build.rs path |
| Version conflicts in Cargo.toml | litesvm pins solana-instruction =3.2.0 | Use `anchor-litesvm 0.4.x` instead of raw litesvm, or pin compatible versions |

### 5. Running tests

```bash
cargo nextest run -p my_program --test master_pda --nocapture
```

Or with standard cargo:
```bash
cargo test -p my_program --test master_pda -- --nocapture
```

## Verification

- `cargo test -p <program>` compiles and passes
- `.so` file is auto-built on first run (delete `target/deploy/<program>.so` to test)
- No version conflicts in `cargo check -p <program> --tests`
