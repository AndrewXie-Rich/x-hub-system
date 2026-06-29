# Governed Autonomy

<p class="lead">
Most agent products have one "autonomy" slider that goes from "ask first" to "do it." X-Hub doesn't. Three independent dials instead — how far execution can go, how deeply Supervisor watches, and how often review fires. So higher autonomy doesn't mean weaker oversight.
</p>

<div class="preview-note">
  <strong>For the A0..A4 / S0..S4 tier table, see <a href="/x-terminal">X-Terminal</a>.</strong>
  The full tier table lives with X-Terminal, where these controls are actually configured.
</div>

## The Model

The active product direction separates several things that most agent products blur together:

- execution range
- supervision depth
- review cadence
- intervention behavior

In practice, that means X-Hub is moving away from one generic autonomy slider and toward a governed model with distinct
execution and supervision tiers, plus explicit review and guidance behavior.

For the fuller explanation of A0..A4, S0..S4, Heartbeat / Review, and the Coder / Supervisor / Hub / User split, see [X-Terminal](/x-terminal).

## What Changes Compared With Typical Agent Autonomy

The important point is not the existence of tiers by itself. The important point is the separation of concerns:

- higher execution range does not automatically erase supervision
- stronger supervision does not have to mean blocking every step synchronously
- review can happen on its own cadence instead of being confused with every progress heartbeat
- corrective guidance can be inserted deliberately instead of being lost in generic chat history

## Heartbeat, Review, And Intervention Are Different

This separation is one of the important product moves:

- heartbeat watches progress
- review judges direction, method, or drift
- intervention injects correction or replan into the execution chain

That matters because too many agent systems blur these concepts into one noisy check-in model.

## Safe-Point Guidance And Acknowledgement

The design direction treats review output as structured runtime state rather than disposable chat.
Corrective guidance should be delivered in a bounded way, surfaced clearly, and handled as part of the operating model
instead of being left to vague prompt interpretation.

## Why This Matters In Practice

The point of governed autonomy is not just more automation. It is more automation that still remains legible and correctable:

- projects can move faster without becoming black-box autopilots
- higher-risk work can be kept under tighter boundaries than lower-risk work
- review depth can increase without forcing synchronous human approval on every step
- correction can be inserted where it is safe and meaningful instead of causing constant manual interruption

## The Result

X-Hub aims for a different tradeoff than "max freedom at all costs":

- more execution range
- clearer runtime ceilings
- stronger correction loop
- more honest evidence of what happened

That is why the system is better described as governed autonomy than as agent autopilot.
