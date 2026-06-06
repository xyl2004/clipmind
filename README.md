# ClipMind

**Highlight Web3 text. Ask AI. Sign locally.**

ClipMind is a macOS AI wallet layer for the moment when a user sees something on-chain and does not yet know what it means or what to do next.

Select a wallet address, token contract, transaction hash, project name, or Web3 paragraph anywhere on macOS. Press `Control + Option + W`. ClipMind opens a floating AI panel that can explain the selection, fetch on-chain evidence, classify the user's intent, and prepare a locally signed EVM wallet action.

## The Problem

Web3 users constantly move between chats, explorers, docs, token pages, and trading tools. The hard part is not only signing a transaction. It is understanding the context before signing:

- What is this address?
- Is this token contract the right one?
- What happened in this transaction?
- Can I send funds here?
- Can I buy this token safely?

Most wallets wait for a dApp transaction request. ClipMind starts earlier: at the selected text.

## The Solution

ClipMind turns selected Web3 text into an AI-guided wallet workflow:

```text
Select Web3 text
-> Open ClipMind with Control + Option + W
-> Ask a natural-language question or command
-> Fetch Surf-backed on-chain context when useful
-> Classify intent: ask, check, transfer, or swap
-> Build a readable transaction plan
-> Validate chain, balance, gas, quote freshness, and risk notes
-> User confirms
-> Local wallet signs
```

AI helps understand and prepare. The local wallet signs only after explicit confirmation.

## Demo Flow

### 1. Ask About Selected Text

Select a wallet address, token contract, transaction hash, project name, or paragraph, then ask:

```text
这个地址安全吗？
这个交易发生了什么？
这个项目是做什么的？
```

ClipMind can answer with selected-text context plus Surf-backed EVM data.

### 2. Send To A Selected Address

Select a wallet address and ask:

```text
给这个地址转 5 USDC
```

ClipMind parses the transfer intent, builds a confirmation plan, checks wallet state, and requires local confirmation before signing.

### 3. Buy A Selected Token

Select a token contract and ask:

```text
用 20U 买这个币
```

ClipMind builds a Uniswap swap plan, shows expected output, gas, quote freshness, approval needs, and safety notes before the user signs.

## Why It Is Different

- **Selection-first UX**: the workflow begins from text the user is already looking at, not from a wallet form.
- **AI-native intent layer**: natural language is converted into structured wallet actions with a rule-based fallback.
- **Evidence before execution**: Surf research can ground answers and checks before a transaction is prepared.
- **Local signing boundary**: private keys stay in macOS Keychain and are never exposed to the LLM.
- **Floating wallet surface**: the wallet appears near the user's current context instead of forcing a tab or app switch.

## Current Capabilities

- Floating macOS context panel opened with `Control + Option + W`.
- Per-selection chat sessions and history.
- EVM research for wallets, tokens, transactions, and projects through Surf CLI.
- Chinese AI explanations through B.AI / DeepSeek.
- LLM-first structured intent classification with rule fallback.
- Read-only checks for balances, addresses, tokens, and transactions.
- User-confirmed transfer and swap planning.
- Uniswap swap quotes for Ethereum, Base, Arbitrum, OP Mainnet, and Polygon.
- Local EVM wallet creation/import with private key storage in macOS Keychain.
- Local signing only after explicit user confirmation.
- Core self-test suite for intent parsing, validation, chain config, wallet assets, and local wallet export checks.

## Safety Model

ClipMind treats AI output as a draft, not authority.

- AI cannot read private keys.
- AI cannot call signing functions directly.
- AI cannot broadcast a transaction without user confirmation.
- Transaction plans must pass validation before signing.
- Expired quotes, invalid addresses, chain mismatches, missing fields, insufficient balance, and gas problems block execution.
- Private-key export requires a separate local confirmation.

## Tech Stack

- SwiftUI macOS app
- Swift Package Manager
- web3swift + secp256k1 local signing
- macOS Keychain
- Surf CLI for on-chain research
- B.AI / DeepSeek for AI explanation and intent classification
- Uniswap Trading API for swap quotes and transactions

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

## Status

ClipMind is an experimental competition build. It demonstrates a selection-first AI wallet workflow where AI helps users understand and prepare actions, while signing remains local and confirmation-gated.
