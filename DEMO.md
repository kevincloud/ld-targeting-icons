# Targeting Visualization

A live grid of 2,000 users, each with a user, device, and organization context. Green squares get `true` from the flag, red squares get `false`. Change targeting in LaunchDarkly and the grid repaints within a second over a WebSocket.

## Talk track (5 minutes)

1. **Start with the flag off.** Everything is red. Open the instance's LaunchDarkly project (link on the demo card) and the `show-feature` flag.
2. **Target a segment.** Add a rule: `plan` is one of `platinum`, `diamond` → true. A slice of the grid turns green as the SDK streams the change. Point out the squares are random users with realistic attributes, so the slice is wherever those users happen to be.
3. **Layer a second rule.** `metro` is `San Francisco` → true. More squares flip. This is how rules compose: first match wins, top to bottom.
4. **Percentage rollout.** Set the default rule to a 25% rollout. Explain bucketing is deterministic per context key, so the same users stay green as you raise it to 50% and 100%.
5. **Kill switch.** Toggle the flag off. Instant, everywhere, no deploy.

The `ROLLOUT_DEMO.md` script in the repo automates step 4 against the instance's project if you want a hands-free progressive rollout.

## Seeded targeting (confirm or change)

The seed starts `show-feature` **on** with two rules and a 0% default rollout, so the first launch already paints a slice of the grid:

| Rule | Why |
| --- | --- |
| `user.beta` is `true` → on | The Admin panel's "mark as beta" control sets this attribute, so hand-picked squares light up immediately. |
| `user.plan` in `platinum`, `diamond` → on | One attribute rule to edit live in step 2. |
| Default rule: 0% / 100% rollout | Seeded as a rollout (not a fixed variation) so `rollout-demo.sh` can raise the weight without converting the default rule first. |

The `beta-testers` segment is created empty for step 2's "add a segment" beat.

## Notes for the presenter

- The flag to visualize is the `FLAG_KEY` launch parameter (default `show-feature`, created by the seed). Any boolean flag in the instance's project works.
- Upload a picture via the page's controls and the green squares reveal it; "beta selection" lets you hand-pick users to show how individual targeting works.
- Public links are allowed for this demo, so you can share the grid in a meeting without SSO.
