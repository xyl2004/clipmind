# ClipMind

ClipMind is a macOS AI wallet for selected Web3 text.

Select an address, token contract, transaction hash, project name, or any Web3 snippet anywhere on macOS. Press `Control + Option + W`, ask a question, and ClipMind turns that selection into grounded AI context, on-chain research, or a user-confirmed wallet action.

The product idea is simple: **highlight first, ask naturally, sign locally**.

## What It Does

- Opens a floating AI context panel from selected text with `Control + Option + W`.
- Keeps one chat thread per selection, so every address, token, tx, or project has its own context.
- Uses Surf CLI to fetch EVM wallet, token, transaction, and project data.
- Uses B.AI / DeepSeek to explain selected Web3 context in Chinese.
- Classifies wallet intents from natural language, including ask, transfer, swap, and read-only checks.
- Builds user-confirmed Uniswap swap plans for Ethereum, Base, Arbitrum, OP Mainnet, and Polygon.
- Creates or imports a local EVM wallet, stores the private key in macOS Keychain, and signs only after explicit user confirmation.
- Provides a core self-test suite for intent parsing, transaction validation, chain config, wallet assets, and local wallet export checks.

## Product Shape

ClipMind has two surfaces:

- **Floating panel**: the high-frequency entry point for selected text, AI questions, and wallet intents.
- **Main window**: the deeper workspace for wallet state, service connections, transaction history, conversation history, full Surf evidence, and advanced management.

The wallet flow is designed around a strict boundary:

```text
AI understands intent
-> ClipMind builds a readable plan
-> ClipMind checks parameters, balance, gas, quote freshness, and risk notes
-> the user reviews a confirmation sheet
-> the local wallet signs
```

AI does not read private keys, call signing functions directly, or broadcast transactions without user confirmation.

## Current Capabilities

### Selected-Text AI

ClipMind can read selected text from other macOS apps with Accessibility permission. If direct selection reading is unavailable, it falls back to a clipboard-based read and restores the previous clipboard content.

Supported context types include:

- EVM wallet addresses
- Token contracts
- Transaction hashes
- Short project names
- Free-form Web3 text

### On-Chain Research

Surf-powered research currently covers:

- Wallet detail and recent transfers
- Token holders, DEX trades, and token transfers
- Transaction details
- Project overview, token info, contracts, social links, and news

### AI Wallet Actions

ClipMind can parse natural-language wallet requests such as:

```text
给这个地址转 5 USDC
用 20U 买这个币
这个地址安全吗？
查一下这笔交易
```

The app uses an LLM-first structured intent classifier with a rule-based fallback. Read-only checks can trigger Surf research or local wallet balance summaries. Transfer and swap intents produce structured plans that must pass validation before signing.

### Local Signing

The local wallet:

- Stores the private key in macOS Keychain.
- Does not store a seed phrase.
- Does not send the private key to the LLM.
- Requires explicit confirmation before signing.
- Allows explicit private-key export only after a second local confirmation.

## Requirements

- macOS 14+
- Xcode 15+ with Swift 5.9 or newer
- Surf CLI
- Accessibility permission for selected-text capture
- Optional B.AI API key for AI explanations and intent classification
- Optional Uniswap API key for swap quotes and transactions

Install Surf if needed:

```bash
curl -fsSL https://downloads.asksurf.ai/cli/releases/install.sh | sh
surf sync
```

Useful environment variables:

```bash
CLIPMIND_BAI_API_KEY=...
CLIPMIND_UNISWAP_API_KEY=...
CLIPMIND_BAI_BASE_URL=https://api.b.ai
CLIPMIND_INTENT_BACKEND=auto   # auto, llm, or rule
CLIPMIND_RPC_ETHEREUM=...
CLIPMIND_RPC_BASE=...
CLIPMIND_RPC_ARBITRUM=...
CLIPMIND_RPC_OPTIMISM=...
CLIPMIND_RPC_POLYGON=...
```

## Run

```bash
./script/build_and_run.sh
```

Useful flags:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

## Test

```bash
./script/test.sh
```

This runs:

```bash
swift run ClipMind --self-test-core
```

The self-test path avoids real network calls and uses isolated test Keychain services. It is the active automated test entrypoint in this workspace.

## Daily Use

1. Select text anywhere on macOS.
2. Press `Control + Option + W`.
3. Ask what the selection means, whether it looks risky, or what action you want to prepare.
4. Review AI answers and Surf-backed context.
5. For wallet actions, review the generated confirmation sheet before local signing.

## Safety Notes

ClipMind is experimental software for a local AI-wallet workflow. Review every transaction before signing, keep small limits while testing, and treat all AI-generated plans as drafts until the confirmation sheet and on-chain details make sense.
