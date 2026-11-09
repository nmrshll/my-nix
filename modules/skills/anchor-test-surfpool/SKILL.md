---
name: anchor-test-surfpool
description: Configure and run Anchor TypeScript integration tests against the surfpool validator, including wallet airdrop, ESM import fixes, and common failure triage.
---

# Anchor Test with Surfpool

Set up and run Anchor TypeScript integration tests against surfpool (bundled in Anchor >1.0), not `solana-test-validator`.

## When to use

- User wants to run `anchor test` for a program
- Tests fail with "Attempt to debit an account" (unfunded wallet)
- Tests fail with ESM module resolution errors (`Cannot find module`, `does not provide an export`)
- User needs to switch from `solana-test-validator` to surfpool

## Prerequisites

- Anchor CLI ≥1.0 (surfpool is bundled)
- Surfpool installed (check: `which surfpool`)
- Wallet keypair file at `.cache/keys/payer.json` or similar

## Steps

### 1. Start surfpool manually (if not using `anchor test`)

```bash
surfpool start --manifest-file-path Anchor.toml \
  --airdrop-keypair-path .cache/keys/payer.json \
  --airdrop <WALLET_PUBKEY>
```

**Key fact:** Surfpool only airdrops to `--airdrop-keypair-path` (default `~/.config/solana/id.json`). If that file doesn't exist, no airdrop occurs. Always pass `--airdrop-keypair-path` explicitly.

### 2. Run anchor test with surfpool flags

```bash
anchor test \
  --program-name <PROGRAM_NAME> \
  --skip-local-validator \
  --provider.wallet .cache/keys/payer.json
```

- `--skip-local-validator` keeps existing surfpool running
- Remove `--skip-deploy` unless the program is already deployed (otherwise: "This program may not be used for executing instructions")

### 3. Fix TypeScript ESM import errors

Anchor 1.x generates types as `export type`. In ESM context (ts-mocha v11), this requires:

**tsconfig.json:**
```json
{
  "compilerOptions": {
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "module": "nodenext",
    "moduleResolution": "nodenext"
  }
}
```

**Import statements:**
```typescript
// WRONG — fails with "does not provide an export named 'X'"
import { MyProgram } from "../target/types/my_program";

// CORRECT — use import type for type-only IDL imports
import type { MyProgram } from "../target/types/my_program.ts";
```

Always add `.ts` extension to local imports in ESM context.

### 4. Common failures and fixes

| Error | Cause | Fix |
|---|---|---|
| `Attempt to debit an account but found no record of a prior credit` | Wallet not funded | Airdrop: `solana airdrop N -k .cache/keys/payer.json --url localhost` or configure surfpool airdrop |
| `This program may not be used for executing instructions` | `--skip-deploy` but program not on-chain | Remove `--skip-deploy` |
| `Cannot find module '../target/types/X'` | Missing `.ts` extension in import | Add `.ts` to import path |
| `does not provide an export named 'X'` | `export type` requires `import type` | Change to `import type { X }` |
| `anchor test` loads ALL `tests/**/*.ts` | `--program-name` filters build/deploy but not mocha glob | Fix broken imports in other test files, or restructure test files per program |

### 5. Anchor.toml test config

The `[scripts]` test entry should use ts-mocha with the full glob:

```toml
[scripts]
test = "yarn run ts-mocha -p ./tsconfig.json -t 1000000 tests/**/*.ts"
```

Note: `--program-name` does NOT filter which test files mocha loads. If other test files have broken imports, they will fail even when filtering to one program.

## Verification

- `anchor test --program-name <NAME> --skip-local-validator` completes without errors
- Surfpool logs (`.surfpool/logs/`) show successful transaction processing
- Test output shows `N passing`
