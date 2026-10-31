---
title: DORA, you have a naming problem
tags: [regulation, devops, compliance]
aliases:
  - DORA
  - Naming problem
date: 2026-10-31
published: false
related: "[[Goals]]"
source: https://dora.dev
---
# DORA, you have a naming problem

Say “DORA” to a room of engineers and most of them will think of the four **DevOps metrics**. Say it to a room of compliance people and they will think of the *Digital Operational Resilience Act*.

Both are about the same thing: how well your systems hold up when something goes wrong. One measures it. The other makes it law.

## Two acronyms, one question

> Can we change our systems quickly without breaking them, and recover fast when we do?

The metrics come from [DevOps Research and Assessment](https://dora.dev). Read them next to the regulation and the overlap is hard to miss:

- **Time to restore** → incident management
- **Change failure rate** → ICT change management
- **Lead time** → `nothing`

The Act has no opinion on speed. See also [[Goals]] and [[Highly performing teams|our teams note]], or [[Missing note]].

## Checklist

- [x] Read the regulation
- [ ] Write the letter
  - [ ] Outline

| Metric | Owner | Target |
|:--|:-:|--:|
| Lead time | Dev | 1 day |
| Time to restore | Ops | 1 hour |

```swift
let answer = 42
```

~~Struck~~ text and a bare link https://dora.dev.

---
