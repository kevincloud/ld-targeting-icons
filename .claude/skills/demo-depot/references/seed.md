<!-- Generated from docs/MANIFEST.md in the demo-depot repo. Don't edit by hand; regenerate it when the schema changes. -->
# LaunchDarkly seed format (seedVersion 1)

```json
{
  "seedVersion": 1,
  "environments": [{ "key": "demo", "name": "Demo", "color": "7B42BC" }],
  "flags": [
    {
      "key": "new-checkout",
      "name": "New checkout",
      "kind": "boolean",
      "variations": [{ "value": true }, { "value": false }],
      "defaults": { "onVariation": 0, "offVariation": 1 },
      "clientSideAvailability": { "usingEnvironmentId": true },
      "environments": {
        "demo": { "on": false, "fallthrough": { "variation": 1 }, "rules": [] }
      }
    }
  ],
  "segments": [
    { "key": "beta-users", "name": "Beta users", "environment": "demo", "included": ["user-123"] }
  ],
  "aiConfigs": [
    {
      "key": "support-agent",
      "name": "Support agent",
      "variations": [
        {
          "key": "default",
          "model": { "id": "anthropic.claude-sonnet" },
          "messages": [{ "role": "system", "content": "You are a helpful support agent." }]
        }
      ]
    }
  ]
}
```

How the importer applies a seed:

1. It applies the environments, then segments, then flags (including targeting), then AI Configs.
2. Each item is idempotent, keyed by `key`.
3. Map the AI Configs shape to the current LaunchDarkly API at implementation time. `dd ld export` must round-trip whatever shape the importer accepts.

## Authoring tips

- Generate the seed from a working project with `dd ld export --project <key>` rather than writing it by hand.
- Give flags a `name` and `description`, because SEs see them in the LaunchDarkly UI during the call.
- Set each flag's starting state (`on`, `fallthrough`) to where the story begins. Usually that means the new experience is off.
- For guarded rollouts or experiments, also seed the metrics the demo emits, once the importer supports them. Until then, document them in DEMO.md under "Setup the SE does".
