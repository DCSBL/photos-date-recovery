<!--
PR title format: <component>(<type>): <short description>
e.g. app(feat): Bulk selection per import · core(fix): Read Signal names with milliseconds
See AGENTS.md for component and type tables.
-->

## Summary

<!-- What changed and why, in 1-3 sentences. -->

## Testing

<!-- e.g. `cd PhtofxrCore && swift test`, CI jobs, manual check in the simulator or on device. -->

## Checklist

- [ ] Follows the layer split (`PhtofxrCore` pure logic, `App` thin) — see AGENTS.md
- [ ] No hard constraint broken (no network, no write without confirmation, journal before write, added date untouched)
- [ ] Tests added or updated in `PhtofxrCore` for new pure logic
- [ ] English and Dutch strings updated in the string catalog for new UI text
- [ ] PLAN.md or docs updated if behavior changed
