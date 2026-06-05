# ClipMind

ClipMind is an EVM multi-chain macOS prototype for a context-aware Ethereum wallet assistant.

The current build focuses on selected-text research, Chinese AI explanation, and user-confirmed Uniswap swaps:

- EVM wallet, token, transaction, and project research through the local Surf CLI (single-chain or automatic multi-chain queries).
- A compact SwiftUI desktop surface that can be opened from the Dock or menu bar.
- Global `Control + Option + W` wake-up into a floating context chat panel.
- Per-selection chat sessions kept in the left-side history so each selection has its own thread.
- Chinese AI explanations through B.AI LLM Service using `deepseek-v4-flash`, with multi-turn context preserved.
- Custom product-style dark UI instead of the default macOS sidebar/list look.
- Uniswap quote/confirmation flow for Ethereum, Base, Arbitrum, OP Mainnet, and Polygon.
- A local EVM hot wallet that stores the private key in macOS Keychain, signs only after user confirmation, and allows explicit private-key export after a second confirmation.

## Requirements

- macOS 14+
- Xcode 15+ (Swift 5.9 toolchain — `swift --version` should report 5.9 or newer)
- Surf CLI on disk (auto-discovered from `~/.local/bin/surf`, `~/.surf/bin/surf`, `/opt/homebrew/bin/surf`, `/usr/local/bin/surf`, or `PATH`)
- **Accessibility permission** for ClipMind (System Settings → Privacy & Security → Accessibility). Required so the global hotkey can read selected text from other apps.
- Optional B.AI API key. Resolution order: `CLIPMIND_BAI_API_KEY` env → legacy `AGENTWALLET_BAI_API_KEY` env → `B_AI_API_KEY` env → macOS Keychain (`AgentWallet.BAIAPIKey`, retained for compatibility).
- Optional Uniswap API key. Resolution order: `CLIPMIND_UNISWAP_API_KEY` env → legacy `AGENTWALLET_UNISWAP_API_KEY` env → `UNISWAP_API_KEY` env → macOS Keychain (`AgentWallet.UniswapAPIKey`, retained for compatibility).
- Optional `CLIPMIND_BAI_BASE_URL` to point at a self-hosted or proxy B.AI-compatible endpoint (defaults to `https://api.b.ai`; legacy `AGENTWALLET_BAI_BASE_URL` is still accepted).
- Optional RPC overrides: `CLIPMIND_RPC_ETHEREUM`, `CLIPMIND_RPC_BASE`, `CLIPMIND_RPC_ARBITRUM`, `CLIPMIND_RPC_OPTIMISM`, `CLIPMIND_RPC_POLYGON`. Legacy `AGENTWALLET_RPC_*` names are still accepted.

Install Surf if needed:

```bash
curl -fsSL https://downloads.asksurf.ai/cli/releases/install.sh | sh
surf sync
```

## Run

```bash
./script/build_and_run.sh
```

Useful flags:

```bash
./script/build_and_run.sh --verify    # build + launch + confirm process is alive
./script/build_and_run.sh --logs      # tail unified-log output
./script/build_and_run.sh --debug     # launch under lldb
```

The Codex app Run action is wired to the same script.

## Test

```bash
./script/test.sh
```

This runs the core self-test suite through `swift run ClipMind --self-test-core`.
It avoids real network calls and uses an isolated test Keychain service for wallet export checks. The local toolchain in this workspace does not expose `XCTest` or Swift `Testing`, so `swift test` is not the active test entrypoint yet.

## Daily use

1. Select text anywhere on macOS — an address, a contract, a tx hash, a project name, or a sentence.
2. Press `Control + Option + W`. A floating panel appears anchored near the selection.
3. The selected text becomes a new context-chat session. Ask the AI follow-up questions in Chinese.
4. For supported inputs (wallet address, EVM contract, tx hash, short project name) ClipMind calls Surf and feeds the structured data plus the chat history to the LLM, so multi-turn answers stay grounded.
5. Switch between historical sessions in the left sidebar — each selection is its own thread.
6. To trade, create or import a local wallet, generate a Uniswap confirmation sheet, then click the local signing button after reviewing route, gas, approval, and risk notes.
