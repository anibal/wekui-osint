title:: Event
type:: concept
status:: built

- An **Event** is a single real-world happening that we are studying, such as a protest, a blackout, or another major occurrence.
- It is the top-level thing in the system: every other piece of information belongs to exactly one Event, and information is never shared between Events.
- An Event has:
  - **Name** — a short label that identifies the Event. No two Events can have the same name.
  - **Time zero** — the moment the Event began. We use it as the reference point in time for everything we collect about the Event.
  - **Goal** — a plain sentence describing what we want to learn or achieve by studying this Event.
  - **Timezone** — the local timezone of the Event. We store it so that, later, we can show times the way people in that place would read them.
- Rules
  - Every Event must have a name, a time zero, and a goal.
  - Each Event's name is unique across the whole system.
  - If no timezone is given, it defaults to `America/Caracas`.
- Every Event has exactly one [[unplaced-place]], which the Event points at directly.
- Everything else belongs to exactly one Event: [[place]], [[search]], [[post]], [[author]].
