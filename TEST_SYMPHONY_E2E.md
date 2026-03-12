# Fizzy Codebase Summary

Fizzy is a Ruby on Rails application for collaborative project management and issue tracking. It is a kanban-style tool where teams organize work on boards, move cards through workflow columns, discuss work with comments and mentions, and manage access for different people inside an account.

The codebase is built around a multi-tenant account model. Each account lives under a URL path prefix, and core domain objects such as users, boards, cards, events, tags, and webhooks are scoped to that account. Authentication is passwordless, background jobs restore account context automatically, and activity is tracked through event records that power timelines, notifications, and integrations.

Technically, Fizzy is a full-stack Rails app with rich domain models, Solid Queue background jobs, Action Text for card content, and sharded full-text search. It also includes import/export support for moving account data between deployments and an "entropy" system that automatically postpones stale cards to keep boards from becoming overloaded.
