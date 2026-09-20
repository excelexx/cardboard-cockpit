> Superseded by [adaptive dual plasma](ADAPTIVE_PLASMA.md): the minigun is now removed, and four-missile salvos launch automatically with area damage.

# Weapon readability and two flocks — 0.17.0

Primary input remains excelex's visible gun tag (ID4), or held Space/left mouse. It now fires minigun and plasma together, as requested. T/right mouse independently fires slow guided missiles. There are no latched switches. The latest request supersedes the earlier gun-only direction; the camera setup, sensitivity/agility menu, two flight modes and tracking recovery remain.

- Minigun: 0.10-second visible packet interval, compact 8.4-metre tracer mesh (under 7% of the inter-packet spacing), narrower distance-based width. No persistent cannon trail ribbon. Rounds originate at the mounted barrel tip and their world-space tails are checked ahead of the aircraft in straight flight.
- Missiles: one per three-second cooldown, rotating through four hardpoints; 3.2× flight-model scale and 2.0× mounted scale. Actual launches, rather than queue requests, increment the fired counter.
- Plasma: 0.24-metre core radius, 0.48-metre braid and 0.88-metre halo, with 100 damage/second while primary is held. The beam starts at the live BeamMuzzle marker. Cover/release stops primary fire; its short release tail decays naturally.
- Machinery: existing authored CG26 rotary cannon and PC26 plasma projector are mounted visibly on the forward chines. Rotor, barrel heat, coil charge and muzzle effects follow real firing state.
- Normal SF: first wave12, a four-second transition, then wave20. Active-wave and total32 tallies count real unique deaths. Assisted flight slows for the flock and aims at individual survivors instead of orbiting an empty centre. The sixteen-target Tutorial stays separate.
- Audio: starts on each launch; M remains available for session mute.

Verification includes the weapon mount/effects contract, firing/cooldown/forward-tracer checks, independent camera controls, exact wave counts and a full SF guided run clearing all32 targets before a stopped landing. Native QA uses isolated aircraft and simulated firing with Bluetooth disabled and Dummy audio. No badge firmware is flashed by this change.
