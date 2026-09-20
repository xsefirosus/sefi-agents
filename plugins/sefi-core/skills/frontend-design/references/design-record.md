# Design Record and Inheritance

Every `state/design-<slug>.md` for BUILD, REDESIGN, or PROTOTYPE contains these sections
once and in this order:

1. Product Context
2. Selected Direction
3. Style Profile and Values
4. Layout Pattern
5. Typography
6. Color Roles
7. Spacing and Shape Rules
8. Signature Element
9. Component and State Behavior
10. Responsive and Mobile Behavior
11. Resilient Content
12. Motion Complexity
13. Accessibility
14. Performance Limits
15. Library Recommendation
16. Alternatives Rejected
17. Evidence and Confidence
18. Master and Page References
19. Review Result
20. Open Questions

Product Context contains Audience, Primary user task, Product and platform, Brand
constraints, Content constraints, Existing design-system constraints, Accessibility
requirements, one anti-reference, Relevant project memory, and Unknown or pending
information. Label each claim as observed facts, design decisions, recommendations, or
unknown information. Reference a master rather than copy its complete token tables.

Create `state/design-system/<project-slug>/MASTER.md` only when the product has more than
one page or screen, multiple implementation tasks need the same visual rules, or the user
explicitly requests a reusable design system. It is the source of truth for shared tokens,
typography, spacing, components, states, accessibility, and interaction rules.

Create `state/design-system/<project-slug>/pages/<page-slug>.md` only for intentional
differences. It records Page purpose, Master file consumed, Intentional differences, Reason
for each difference, Components affected, Responsive differences, Page-specific interaction
or motion, and Review evidence. If no page override exists, the master applies unchanged.
Page rules may never weaken accessibility, keyboard support, touch-target, reduced-motion,
or resilient-content requirements. Existing flat `state/design-<slug>.md` files remain
readable; never move or delete user-owned files automatically.
