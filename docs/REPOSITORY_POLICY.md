# Repository policy

## Change discipline

- Each commit should represent one reviewable outcome.
- Specifications should precede behavior they authorize.
- Contract behavior changes require tests in the same commit or an immediately
  adjacent test-first commit.
- Do not rewrite published history to manufacture development activity.
- Do not commit generated build output unless it is required submission
  evidence and explicitly documented.

## Prompt and AI records

- Number material development prompts sequentially under `prompts/`.
- Record material AI assistance in `docs/AI_USAGE.md`.
- Human approval is required for economic assumptions, trust boundaries,
  security exceptions, and final claims.
- Generated output is not accepted solely because it compiles or passes a
  narrow test.

## Security hygiene

- Never commit private keys, seed phrases, access tokens, populated `.env`
  files, or private RPC credentials.
- Use dedicated test wallets with limited funds.
- Treat external price and volatility inputs as untrusted until their validation
  and freshness rules are specified.
- Preserve deployment addresses, chain IDs, source versions, constructor
  arguments, and verification links as submission evidence.

## Definition of done for a feature

A feature is complete only when its specification, implementation, tests,
user-visible behavior, and documentation agree. Any missing element must remain
visible in the project status rather than being implied complete.

