# Cross-Chain Rebase Token

A cross-chain rebase token protocol built with **Solidity, Foundry, Chainlink CCIP, and OpenZeppelin**.

The project combines a time-based interest-bearing ERC-20 token with a vault and Chainlink CCIP to allow the token to move between supported EVM chains while preserving the user's interest rate.

## Overview

Users can deposit ETH into the `Vault` and receive an equivalent amount of `RebaseToken (RBT)`.

Unlike a normal ERC-20 token, the user's effective balance grows over time according to an interest rate assigned when the user deposits.

The protocol uses a **global interest rate** that can only decrease. Each user receives a snapshot of the current rate when they enter the protocol, so earlier depositors can retain a higher rate even after the global rate is reduced.

The project extends this mechanism across chains using **Chainlink CCIP**.

## Core Features

* ETH deposits through a Vault
* Rebase token whose balance grows linearly with time
* Individual interest rate assigned to each user
* Global protocol interest rate can only decrease
* Interest is accounted for during mint, burn, and transfer operations
* Users can redeem their rebase tokens for ETH
* Cross-chain token transfers using Chainlink CCIP
* Custom CCIP `RebaseTokenPool`
* User interest rate is preserved during cross-chain transfers
* Foundry-based testing, deployment, and scripting

## How the Rebase Mechanism Works

When a user deposits ETH:

```text
User
  │
  │ deposit ETH
  ▼
Vault
  │
  │ reads current protocol interest rate
  ▼
RebaseToken
  │
  │ mints tokens
  ▼
User
```

The user's interest rate is stored at the time of the deposit.

For example:

```text
Initial protocol rate = 5e10

User A deposits
→ User A gets 5e10 interest rate

Protocol rate decreases to 4e10

User B deposits
→ User B gets 4e10 interest rate
```

User A keeps their previously assigned rate.

The token calculates the user's effective balance using the stored interest rate and elapsed time. Accrued interest is materialized into actual token balance when the user performs actions such as minting, burning, or transferring.

The global interest rate is restricted so that it can only move downward.

## Vault

The `Vault` is the entry and exit point for the underlying ETH.

### Deposit

```solidity
vault.deposit{value: amount}();
```

The Vault:

1. Receives ETH.
2. Reads the current protocol interest rate.
3. Mints RebaseTokens to the user.
4. Stores the user's interest-rate snapshot through the token.

### Redeem

```solidity
vault.redeem(amount);
```

The Vault:

1. Burns the user's RebaseTokens.
2. Sends the corresponding ETH back to the user.

The Vault gives the rebase token its underlying ETH-backed entry and exit mechanism.

## RebaseToken

`RebaseToken` is an ERC-20 token with additional interest-accounting logic.

Main components include:

* `ERC20`
* `AccessControl`
* `Ownable`
* Per-user interest rates
* Timestamp tracking
* Dynamic balance calculation
* Controlled minting and burning

The token's `balanceOf()` calculates the user's balance including accrued interest. The contract also materializes accrued interest before important state-changing operations.

### Important Functions

```text
mint()
burn()
balanceOf()
transfer()
transferFrom()
setInterestRate()
getUserInterestRate()
getUserPrincipleBalance()
getProtocolsCurrentInterestRate()
```

Only accounts/contracts granted the `MINT_AND_BURN_ROLE` can mint and burn tokens.

## Cross-Chain Architecture

The cross-chain component uses **Chainlink Cross-Chain Interoperability Protocol (CCIP)**.

Each supported chain has:

```text
RebaseToken
     │
     ▼
RebaseTokenPool
     │
     ▼
CCIP Router
     │
     ▼
Chainlink CCIP
     │
     ▼
Remote CCIP Router
     │
     ▼
Remote RebaseTokenPool
     │
     ▼
Remote RebaseToken
```

The project uses a custom `RebaseTokenPool` that extends Chainlink's `TokenPool`.

## RebaseTokenPool

The custom pool implements the cross-chain behavior required by the rebase token.

### Source Chain

When tokens are bridged, the pool:

1. Validates the CCIP request.
2. Retrieves the sender's interest rate.
3. Burns the tokens involved in the transfer.
4. Encodes the user's interest rate into the pool data.
5. Sends the relevant token and pool information through CCIP.

```text
User
  │
  │ bridge tokens
  ▼
Source RebaseTokenPool
  │
  ├── read user's interest rate
  ├── burn tokens
  └── encode interest rate
          │
          ▼
       CCIP Message
```

### Destination Chain

When the CCIP message reaches the destination pool:

1. The pool validates the message.
2. It decodes the interest rate sent by the source pool.
3. It mints the destination RebaseTokens to the receiver.
4. The receiver receives tokens with the same interest-rate information.

```text
CCIP Message
     │
     ▼
Destination RebaseTokenPool
     │
     ├── decode interest rate
     ├── mint tokens
     └── assign user's rate
             │
             ▼
           User
```

This is the key part that allows the rebase behavior to continue across chains.

## Pool Configuration

Before tokens can be bridged, the TokenPools on both chains need to know about their corresponding remote pool and token.

The `ConfigurePool` script uses Chainlink's `TokenPool.applyChainUpdates()` to configure:

* Remote chain selector
* Remote TokenPool address
* Remote token address
* Outbound rate limiter
* Inbound rate limiter

For example:

```text
Sepolia Pool
    │
    ├── Remote Chain Selector → Arbitrum Sepolia
    ├── Remote Pool           → Arbitrum TokenPool
    └── Remote Token          → Arbitrum RebaseToken
```

The reverse configuration is also required when supporting transfers in the opposite direction.

## Bridging Flow

The `BridgeTokens` script constructs a CCIP `EVM2AnyMessage` and sends the token through the source chain's CCIP Router.

The basic flow is:

```text
1. User owns RebaseTokens
        ↓
2. Approve CCIP Router
        ↓
3. Create EVM2AnyMessage
        ↓
4. Calculate CCIP fee
        ↓
5. Approve LINK for the fee
        ↓
6. Call ccipSend()
        ↓
7. Source TokenPool burns tokens
        ↓
8. User interest rate is included in pool data
        ↓
9. CCIP delivers the message
        ↓
10. Destination TokenPool receives it
        ↓
11. Destination pool decodes interest rate
        ↓
12. Destination RebaseToken is minted
        ↓
13. User receives tokens
```

The bridge script uses the destination chain selector, source router, receiver, source token, amount, and source-chain LINK token to construct and send the CCIP message.

## Deployment Architecture

The project is designed around separate deployments on each chain.

### 1. Deploy on Source Chain

Deploy:

```text
RebaseToken
RebaseTokenPool
```

and register the token/pool with the CCIP token administration system.

### 2. Deploy on Destination Chain

Deploy the corresponding:

```text
RebaseToken
RebaseTokenPool
```

on the destination chain.

### 3. Configure Both Pools

Configure:

```text
Source Pool → Destination Pool + Destination Token

Destination Pool → Source Pool + Source Token
```

### 4. Bridge

Use `BridgeTokens.s.sol` from the source chain.

## Example Cross-Chain Flow

For:

```text
Sepolia → Arbitrum Sepolia
```

the important values are:

```text
Destination Chain Selector
        ↓
Arbitrum Sepolia selector

Local Router
        ↓
Sepolia CCIP Router

Local Token
        ↓
Sepolia RebaseToken

LINK
        ↓
Sepolia LINK

Receiver
        ↓
Destination user

Amount
        ↓
Amount of RBT to bridge
```

The bridge transaction is executed on the source chain because `ccipSend()` is called on the source chain's Router.

## Project Structure

```text
ccip-rebase-token/
│
├── src/
│   ├── RebaseToken.sol
│   ├── RebaseTokenPool.sol
│   ├── Vault.sol
│   └── interfaces/
│       └── IRebaseToken.sol
│
├── script/
│   ├── ConfigurePool.s.sol
│   └── BridgeTokens.s.sol
│
├── test/
│   └── RebaseTokenTest.t.sol
│
├── lib/
│   ├── ccip/
│   ├── chainlink-local/
│   └── openzeppelin-contracts/
│
├── foundry.toml
├── foundry.lock
└── README.md
```

The repository uses Foundry with `src`, `script`, `test`, and `lib` directories, and configures remappings for OpenZeppelin, Chainlink CCIP, and Chainlink Local.

## Testing

The project includes tests covering important rebase-token behavior, including:

* Interest accumulation over time
* Depositing and redeeming
* Transfers
* Interest-rate inheritance during transfers
* Interest-rate reduction
* Access control for minting and burning
* Principal balance tracking
* User-specific interest rates
* Protection against increasing the global interest rate

The tests use Foundry's time-warping and fuzzing capabilities to verify the time-dependent behavior of the token.

Run the test suite with:

```bash
forge test
```

Run with detailed traces:

```bash
forge test -vvv
```

Format the project:

```bash
forge fmt
```

## Tech Stack

* **Solidity** — Smart contracts
* **Foundry** — Development, testing, scripting, and deployment
* **OpenZeppelin** — ERC-20, ownership, and access control
* **Chainlink CCIP** — Cross-chain token transfer
* **Chainlink Local** — Local/fork-based CCIP testing

## Key Design Idea

The main idea behind the project is to combine two concepts:

### Rebase Token

A user's token balance increases with time according to their individual interest rate.

### Cross-Chain Token

The same rebase position can be moved between chains using CCIP while carrying the user's interest-rate information across the bridge.

Therefore, the bridge is not simply transferring an ordinary ERC-20 balance. It also transfers the information required to preserve the user's rebase behavior.

## Security Considerations

This project is intended as a learning and development project and has **not been presented as production-audited software**.

Important areas for further security review include:

* Access control around minting and burning
* TokenPool configuration
* Cross-chain message validation
* Interest-rate handling
* Accounting between the Vault and RebaseToken
* CCIP configuration and token registration
* Rate limiter configuration
* Cross-chain replay and message integrity assumptions

Do not use the contracts with real funds without an appropriate security review and production hardening.

## References

* [Chainlink CCIP](https://github.com/smartcontractkit/chainlink-ccip)
* [Foundry](https://book.getfoundry.sh/)
* [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)

## Author

**Koushik Rawal**

GitHub: [@Koushikrawal22](https://github.com/Koushikrawal22)
